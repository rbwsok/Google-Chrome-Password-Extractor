unit GoogleChromePassword;

interface

uses Winapi.Windows, System.SysUtils, System.Classes, System.JSON, System.NetEncoding,
  System.AnsiStrings, Generics.Collections, SQLiteTable3, SQLite3;

type
  TLoginData = class
  private
    FActionURL: String;
    FOriginURL: String;
    FUserName: String;
    FPassword: String;
    FPairs: TStringList;
  public
    constructor Create;
    destructor Destroy; override;

    property ActionURL: String read FActionURL write FActionURL;
    property OriginURL: String read FOriginURL write FOriginURL;
    property UserName: String read FUserName write FUserName;
    property Password: String read FPassword write FPassword;
    property Pairs: TStringList read FPairs;
  end;

  BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO = record
    cbSize: Integer;
    dwInfoVersion: Integer;
    pbNonce: PByte;
    cbNonce: Integer;
    pbAuthData: PByte;
    cbAuthData: Integer;
    pbTag: PByte;
    cbTag: Integer;
    pbMacContext: PByte;
    cbMacContext: Integer;
    cbAAD: Integer;
    cbData: Int64;
    dwFlags: Integer;
  end;

  TGoogleChromePasswordExtractor = class
  private
    FProfiles: TStringList;
    FLogins: TObjectList<TLoginData>;

    function DPAPIUnprotectData(AData: TBytes): TBytes;
    function MaxAuthTagSize(AAlgoritmHandle: THandle): Integer;
    function DecryptChromePassword(const APassword: RawByteString; const AMasterKey: RawByteString): String;
    function OpenAlgorithmProvider(const AAlgoritm, AProvider, AChainingMode: string): THandle;
    function GetProperty(AAlgoritmHandle: THandle; const APropertyName: String): RawByteString;
    function ImportKey(AAlgoritmHandle: THandle; const AKey: RawByteString; var AKeyHandle: THandle): THandle;
    procedure SetAuthData(var ACipherModeInfo: BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO;
      const AInitializationVector, AAuthenticatedData, ATag: RawByteString);
    procedure FreeAuthData(var ACipherModeInfo: BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO);
    function GetMasterKey(const ABaseDirectory: String): RawByteString;
    procedure ParsePairsBlob(const APairsRawData: RawByteString; APairs: TStringList);
  public
    procedure GetAllProfiles(const ABaseDirectory: String);

    function GetLogins(const ABaseDirectory, AProfileDatabase: String): Boolean;

    constructor Create;
    destructor Destroy; override;

    property Profiles: TStringList read FProfiles;
    property Logins: TObjectList<TLoginData> read FLogins;
  end;

  PDATA_BLOB = ^DATA_BLOB;

  DATA_BLOB = record
    cbData: DWORD;
    pbData: LPBYTE;
  end;

  PCRYPTPROTECT_PROMPTSTRUCT = ^CRYPTPROTECT_PROMPTSTRUCT;

  CRYPTPROTECT_PROMPTSTRUCT = record
    cbSize: DWORD;
    dwPromptFlags: DWORD;
    hwndApp: HWND;
    szPrompt: LPCWSTR;
  end;

  LPLPWSTR = ^LPWSTR;

  BCRYPT_ALG_HANDLE = THandle;
  BCRYPT_HANDLE = THandle;
  BCRYPT_KEY_HANDLE = THandle;

  TNTStatus = LONG;

function CryptUnprotectData(pDataIn: PDATA_BLOB; ppszDataDescr: LPLPWSTR; pOptionalEntropy: PDATA_BLOB;
  pvReserved: PVOID; pPromptStruct: PCRYPTPROTECT_PROMPTSTRUCT; dwFlags: DWORD; pDataOut: PDATA_BLOB): BOOL; stdcall;
  external 'crypt32.dll';

function BCryptOpenAlgorithmProvider(out phAlgorithm: BCRYPT_ALG_HANDLE; pszAlgId, pszImplementation: LPCWSTR;
  dwFlags: ULONG): TNTStatus; stdcall; external 'bcrypt.dll';

function BCryptGetProperty(hObject: BCRYPT_HANDLE; pszProperty: LPCWSTR; pbOutput: PUCHAR; cbOutput: ULONG;
  out pcbResult: ULONG; dwFlags: ULONG): TNTStatus; stdcall; external 'bcrypt.dll';

function BCryptSetProperty(hObject: BCRYPT_HANDLE; pszProperty: LPCWSTR; pbInput: PUCHAR; cbInput: ULONG;
  dwFlags: ULONG): TNTStatus; stdcall; external 'bcrypt.dll';

function BCryptCloseAlgorithmProvider(hAlgorithm: BCRYPT_ALG_HANDLE; dwFlags: ULONG): TNTStatus; stdcall;
  external 'bcrypt.dll';

function BCryptImportKey(hAlgorithm: BCRYPT_ALG_HANDLE; hImportKey: BCRYPT_KEY_HANDLE; pszBlobType: LPCWSTR;
  out phKey: BCRYPT_KEY_HANDLE; pbKeyObject: PUCHAR; cbKeyObject: ULONG; pbInput: PUCHAR; cbInput, dwFlags: ULONG)
  : TNTStatus; stdcall; external 'bcrypt.dll';

function BCryptDecrypt(hKey: BCRYPT_KEY_HANDLE; pbInput: PUCHAR; cbInput: ULONG; pPaddingInfo: Pointer; pbIV: PUCHAR;
  cbIV: ULONG; pbOutput: PUCHAR; cbOutput: ULONG; out pcbResult: ULONG; dwFlags: ULONG): TNTStatus; stdcall;
  external 'bcrypt.dll';

function BCryptDestroyKey(hKey: BCRYPT_KEY_HANDLE): TNTStatus; stdcall; external 'bcrypt.dll';

const
  BCRYPT_CHAINING_MODE = 'ChainingMode';
  BCRYPT_CHAIN_MODE_GCM: String = 'ChainingModeGCM';
  BCRYPT_OBJECT_LENGTH = 'ObjectLength';
  BCRYPT_KEY_DATA_BLOB_MAGIC = $4D42444B;
  BCRYPT_KEY_DATA_BLOB = 'KeyDataBlob';
  BCRYPT_AES_ALGORITHM = 'AES';
  MS_PRIMITIVE_PROVIDER = 'Microsoft Primitive Provider';

implementation

{ TRGoogleChromePasswordExtractor }

constructor TGoogleChromePasswordExtractor.Create;
begin
  FProfiles := TStringList.Create;
  FLogins := TObjectList<TLoginData>.Create;
end;

destructor TGoogleChromePasswordExtractor.Destroy;
begin
  Logins.Free;
  Profiles.Free;
  inherited;
end;

// BaseDirectory - User Data directory for the Chrome-based browser
// Chrome - C:\Users\<username>\AppData\Local\Google\Chrome\User Data\
// Vivaldi - C:\Users\<username>\AppData\Local\Vivaldi\User Data\
// MS Edge - C:\Users\<username>\AppData\Local\Microsoft\Edge\User Data\
// etc ...
procedure TGoogleChromePasswordExtractor.GetAllProfiles(const ABaseDirectory: String);

  procedure GetSubDirectories(const ADirectory: String; var AFileNames: TStringList);
  var
    LSearchRec: TSearchRec;
    LFindResult: Integer;
    LMask: String;
  begin
    if AFileNames = nil then
      exit;

    LMask := IncludeTrailingPathDelimiter(ADirectory) + '*.*';

    ZeroMemory(@LSearchRec, sizeof(TSearchRec));
    LFindResult := System.SysUtils.FindFirst(LMask, faDirectory, LSearchRec);
    try
      while LFindResult = 0 do
      begin
        if (LSearchRec.attr and faDirectory) <> 0 then
        begin
          if (LSearchRec.name <> '.') and (LSearchRec.name <> '..') then
          begin
            AFileNames.Add(LSearchRec.name);
          end;
        end;
        LFindResult := System.SysUtils.FindNext(LSearchRec);
      end;
    finally
      System.SysUtils.FindClose(LSearchRec);
    end;
  end;

var
  LDirectory: String;
  LStr: String;
  LProfileList: TStringList;
  i: Integer;
begin
  Profiles.Clear;
  LDirectory := IncludeTrailingPathDelimiter(ABaseDirectory);
  LStr := LDirectory + 'Default\Login Data';
  if FileExists(LStr) then
    Profiles.Add(LStr);
  LStr := LDirectory + 'Login Data';
  if FileExists(LStr) then
    Profiles.Add(LStr);

  LProfileList := TStringList.Create;
  try
    GetSubDirectories(LDirectory, LProfileList);
    for i := 0 to LProfileList.Count - 1 do
    begin
      if pos('profile', LowerCase(LProfileList[i])) > 0 then
      begin
        LStr := IncludeTrailingPathDelimiter(LDirectory + LProfileList[i]) + 'Login Data';
        if FileExists(LStr) then
          Profiles.Add(LStr);
      end;
    end;
  finally
    LProfileList.Free;
  end;
end;

function TGoogleChromePasswordExtractor.GetLogins(const ABaseDirectory, AProfileDatabase: String): Boolean;

  function GetTempDirectory: String;
  var
    LPath: array [0 .. MAX_PATH] of WideChar;
  begin
    ZeroMemory(@LPath, sizeof(LPath));
    GetTempPath(MAX_PATH, @LPath);
    result := IncludeTrailingPathDelimiter(LPath);
  end;

  function GetTempFilename(const APath: String): String;
  var
    TempFileName: array [0 .. MAX_PATH] of Char;
  begin
    // Создает файл в папке с уникальным именем и 0 длиной
    GetTempFileNameW(PWideChar(APath), 'fxt', 0, TempFileName);
    result := TempFileName;
  end;

var
  LMasterKey: RawByteString;
  LPassword: RawByteString;
  LTempDBFileName: String;
  LSQLDB: TSQLiteDatabase;
  LSQLquery: String;
  LSQLTable: TSQLiteTable;

  LLoginData: TLoginData;
  LPairsRawData: RawByteString;
begin
  result := false;

  if FileExists(AProfileDatabase) = false then
    exit;

  Logins.Clear;

  LMasterKey := GetMasterKey(ABaseDirectory);

  LTempDBFileName := GetTempFilename(GetTempDirectory);
  Winapi.Windows.CopyFile(PChar(AProfileDatabase), PChar(LTempDBFileName), false);

  LSQLDB := TSQLiteDatabase.Create(UTF8Encode(LTempDBFileName));
  try
    LSQLquery := 'select * from logins';
    LSQLTable := LSQLDB.GetTable(LSQLquery);
    LSQLTable.MoveFirst;

    try
      while LSQLTable.EOF = false do
      begin
        LLoginData := TLoginData.Create;
        LLoginData.ActionURL := LSQLTable.ByNameAsString('action_url');
        LLoginData.OriginURL := LSQLTable.ByNameAsString('origin_url');
        LLoginData.UserName := LSQLTable.ByNameAsString('username_value');
        LPassword := LSQLTable.ByNameAsBlobString('password_value');
        LLoginData.Password := DecryptChromePassword(LPassword, LMasterKey);

        LPairsRawData := LSQLTable.ByNameAsBlobString('possible_username_pairs');
        if Length(LPairsRawData) > 4 then
          ParsePairsBlob(LPairsRawData, LLoginData.Pairs);

        Logins.Add(LLoginData);

        LSQLTable.Next;
      end;

    finally
      FreeAndNil(LSQLTable);
    end;
  finally
    FreeAndNil(LSQLDB);
  end;

  result := true;
end;

function TGoogleChromePasswordExtractor.GetMasterKey(const ABaseDirectory: String): RawByteString;
var
  LStringList: TStringList;
  LValue: TJSONValue;
  LJSONValue: TJSONValue;
  LJSONObject: TJSONObject;
  LData: TBytes;
  LUnprotectData: TBytes;
begin
  result := '';
  if FileExists(ABaseDirectory + 'Local State') = false then
    exit;

  LStringList := TStringList.Create;
  try
    LStringList.LoadFromFile(ABaseDirectory + 'Local State');

    LValue := TJSONObject.ParseJSONValue(LStringList.Text);

    try
      LJSONObject := LValue.GetValue<TJSONObject>('os_crypt');
      LJSONValue := LJSONObject.GetValue<TJSONValue>('encrypted_key');
      LData := TNetEncoding.Base64.DecodeStringToBytes(LJSONValue.value);
      LData := Copy(LData, 5, Length(LData) - 5);
      LUnprotectData := DPAPIUnprotectData(LData);

      SetLength(result, Length(LUnprotectData));
      CopyMemory(@result[1], @LUnprotectData[0], Length(LUnprotectData));
    finally
      FreeAndNil(LValue);
    end;
  finally
    FreeAndNil(LStringList);
  end;
end;

function TGoogleChromePasswordExtractor.DPAPIUnprotectData(AData: TBytes): TBytes;
var
  LDataIn: DATA_BLOB;
  LDataOut: DATA_BLOB;
begin
  LDataOut.cbData := 0;
  LDataOut.pbData := nil;

  LDataIn.cbData := Length(AData);
  LDataIn.pbData := @AData[0];

  if CryptUnprotectData(@LDataIn, nil, nil, nil, nil, 0, @LDataOut) = false then
  begin
    // err := GetLastError;
    exit;
  end;

  SetLength(result, LDataOut.cbData);
  move(LDataOut.pbData^, result[0], LDataOut.cbData);
  LocalFree(HLOCAL(LDataOut.pbData));
end;

function TGoogleChromePasswordExtractor.OpenAlgorithmProvider(const AAlgoritm, AProvider,
  AChainingMode: string): THandle;
var
  LAlgoritmHandle: THandle;
  LStatus: Cardinal;
begin
  LStatus := BCryptOpenAlgorithmProvider(LAlgoritmHandle, @AAlgoritm[1], @AProvider[1], 0);
  if LStatus <> ERROR_SUCCESS then
    exit(1);

  LStatus := BCryptSetProperty(LAlgoritmHandle, BCRYPT_CHAINING_MODE, @AChainingMode[1], Length(AChainingMode), 0);
  if LStatus <> ERROR_SUCCESS then
    exit(1);

  result := LAlgoritmHandle;
end;

function TGoogleChromePasswordExtractor.GetProperty(AAlgoritmHandle: THandle; const APropertyName: String)
  : RawByteString;
var
  LSize: Cardinal;
  LStatus: Cardinal;
begin
  LSize := 0;

  LStatus := BCryptGetProperty(AAlgoritmHandle, @APropertyName[1], nil, 0, LSize, 0);
  if LStatus <> ERROR_SUCCESS then
    exit;

  SetLength(result, LSize);
  LStatus := BCryptGetProperty(AAlgoritmHandle, @APropertyName[1], @result[1], Length(result), LSize, 0);
  if LStatus <> ERROR_SUCCESS then
    exit;
end;

function TGoogleChromePasswordExtractor.ImportKey(AAlgoritmHandle: THandle; const AKey: RawByteString;
  var AKeyHandle: THandle): THandle;

  function Int32ToString(AValue: Integer): RawByteString;
  begin
    result := '    ';

    result[1] := ansichar(AValue and $FF);
    result[2] := ansichar((AValue and $FF00) shr 8);
    result[3] := ansichar((AValue and $FF0000) shr 16);
    result[4] := ansichar((AValue and $FF000000) shr 24);
  end;

var
  LObjLength: RawByteString;
  LKeyBlob: RawByteString;
  LKeyDataSize: Integer;
  LStatus: Cardinal;
begin
  LObjLength := GetProperty(AAlgoritmHandle, BCRYPT_OBJECT_LENGTH);
  LKeyDataSize := PInteger(@LObjLength[1])^;
  result := LocalAlloc(LMEM_FIXED, LKeyDataSize);
  LKeyBlob := Int32ToString(BCRYPT_KEY_DATA_BLOB_MAGIC) + Int32ToString(1) + Int32ToString(Length(AKey)) + AKey;
  LStatus := BCryptImportKey(AAlgoritmHandle, 0, BCRYPT_KEY_DATA_BLOB, AKeyHandle, PUCHAR(result), LKeyDataSize,
    @LKeyBlob[1], Length(LKeyBlob), 0);
  if LStatus <> ERROR_SUCCESS then
    exit;
end;

procedure TGoogleChromePasswordExtractor.SetAuthData(var ACipherModeInfo: BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO;
  const AInitializationVector, AAuthenticatedData, ATag: RawByteString);
const
  BCRYPT_INIT_AUTH_MODE_INFO_VERSION: Integer = $00000001;
begin
  ACipherModeInfo.cbNonce := 0;
  ACipherModeInfo.pbNonce := nil;
  ACipherModeInfo.cbAuthData := 0;
  ACipherModeInfo.pbAuthData := nil;
  ACipherModeInfo.cbTag := 0;
  ACipherModeInfo.pbTag := nil;
  ACipherModeInfo.pbMacContext := nil;
  ACipherModeInfo.cbMacContext := 0;
  ACipherModeInfo.cbAAD := 0;
  ACipherModeInfo.cbData := 0;
  ACipherModeInfo.dwFlags := 0;

  ACipherModeInfo.dwInfoVersion := BCRYPT_INIT_AUTH_MODE_INFO_VERSION;
  ACipherModeInfo.cbSize := sizeof(BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO);

  if Length(AInitializationVector) > 0 then
  begin
    ACipherModeInfo.cbNonce := Length(AInitializationVector);
    ACipherModeInfo.pbNonce := PByte(LocalAlloc(LMEM_FIXED, ACipherModeInfo.cbNonce));
    CopyMemory(ACipherModeInfo.pbNonce, @AInitializationVector[1], ACipherModeInfo.cbNonce);
  end;

  if Length(AAuthenticatedData) > 0 then
  begin
    ACipherModeInfo.cbAuthData := Length(AAuthenticatedData);
    ACipherModeInfo.pbAuthData := PByte(LocalAlloc(LMEM_FIXED, ACipherModeInfo.cbAuthData));
    CopyMemory(ACipherModeInfo.pbAuthData, @AAuthenticatedData[1], ACipherModeInfo.cbAuthData);
  end;

  if Length(ATag) > 0 then
  begin
    ACipherModeInfo.cbTag := Length(ATag);
    ACipherModeInfo.pbTag := PByte(LocalAlloc(LMEM_FIXED, ACipherModeInfo.cbTag));
    CopyMemory(ACipherModeInfo.pbTag, @ATag[1], ACipherModeInfo.cbTag);
    ACipherModeInfo.cbMacContext := Length(ATag);
    ACipherModeInfo.pbMacContext := PByte(LocalAlloc(LMEM_FIXED, ACipherModeInfo.cbMacContext));
  end;
end;

procedure TGoogleChromePasswordExtractor.FreeAuthData(var ACipherModeInfo: BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO);
begin
  LocalFree(THandle(ACipherModeInfo.pbNonce));
  LocalFree(THandle(ACipherModeInfo.pbAuthData));
  LocalFree(THandle(ACipherModeInfo.pbTag));
  LocalFree(THandle(ACipherModeInfo.pbMacContext));
end;

function TGoogleChromePasswordExtractor.MaxAuthTagSize(AAlgoritmHandle: THandle): Integer;
var
  LTagLengthValue: RawByteString;
const
  BCRYPT_AUTH_TAG_LENGTH: String = 'AuthTagLength';
begin
  LTagLengthValue := GetProperty(AAlgoritmHandle, BCRYPT_AUTH_TAG_LENGTH);
  result := PInteger(@LTagLengthValue[5])^;
end;

function TGoogleChromePasswordExtractor.DecryptChromePassword(const APassword: RawByteString;
  const AMasterKey: RawByteString): String;
var
  LDataIn: TBytes;
  LDataOut: TBytes;
  LPasswordHeader: RawByteString;
  LInitializationVector: RawByteString;
  LPasswordData: RawByteString;

  LAlgoritmHandle: THandle;
  LKeyHandle: THandle;
  LKeyBuffHandle: THandle;
  LAuthCipherModeInfo: BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO;
  LInitializationVectorData: RawByteString;
  LTag: RawByteString;
  LPlainText: RawByteString;
  LPlainTextSize: Cardinal;
  LStatus: Cardinal;
begin
  LPlainText := '';

  LPasswordHeader := System.AnsiStrings.LeftStr(APassword, 3);
  if (LPasswordHeader = 'v10') or (LPasswordHeader = 'v11') then
  begin
    // для chrome >= 80
    LInitializationVector := System.AnsiStrings.MidStr(APassword, 4, 12);
    LPasswordData := System.AnsiStrings.RightStr(APassword, Length(APassword) - (12 + 3));

    LAlgoritmHandle := OpenAlgorithmProvider(BCRYPT_AES_ALGORITHM, MS_PRIMITIVE_PROVIDER, BCRYPT_CHAIN_MODE_GCM);
    LKeyBuffHandle := ImportKey(LAlgoritmHandle, AMasterKey, LKeyHandle);

    try
      LTag := System.AnsiStrings.RightStr(LPasswordData, 16);
      SetLength(LPasswordData, Length(LPasswordData) - 16);

      SetAuthData(LAuthCipherModeInfo, LInitializationVector, '', LTag);

      try
        SetLength(LInitializationVectorData, MaxAuthTagSize(LAlgoritmHandle));

        LPlainTextSize := 0;
        LStatus := BCryptDecrypt(LKeyHandle, @LPasswordData[1], Length(LPasswordData), @LAuthCipherModeInfo,
          @LInitializationVectorData[1], Length(LInitializationVectorData), nil, 0, LPlainTextSize, 0);
        if LStatus <> ERROR_SUCCESS then
          exit;
        SetLength(LPlainText, LPlainTextSize);
        LStatus := BCryptDecrypt(LKeyHandle, @LPasswordData[1], Length(LPasswordData), @LAuthCipherModeInfo,
          @LInitializationVectorData[1], Length(LInitializationVectorData), @LPlainText[1], Length(LPlainText),
          LPlainTextSize, 0);
        if LStatus <> ERROR_SUCCESS then
          exit;
      finally
        FreeAuthData(LAuthCipherModeInfo);
      end;
    finally
      BCryptDestroyKey(LKeyHandle);
      LocalFree(LKeyBuffHandle);
      BCryptCloseAlgorithmProvider(LAlgoritmHandle, 0);
    end;

    result := UTF8ToString(LPlainText);
  end
  else
  begin
    // chrome < 80
    SetLength(LDataIn, Length(APassword));
    CopyMemory(@LDataIn[0], @APassword[1], Length(APassword));
    LDataOut := DPAPIUnprotectData(LDataIn);
    if Length(LDataOut) = 0 then
      result := ''
    else
      result := TEncoding.Unicode.GetString(LDataOut);
  end;
end;

procedure TGoogleChromePasswordExtractor.ParsePairsBlob(const APairsRawData: RawByteString; APairs: TStringList);

  function GetInt32FromString(const AString: RawByteString; AIndex: Integer): Integer;
  begin
    result := 0;
    if AIndex > Length(AString) - 3 then
      exit;

    result := Integer(AString[AIndex]) or (Integer(AString[AIndex + 1]) shl 8) or (Integer(AString[AIndex + 2]) shl 16)
      or (Integer(AString[AIndex + 3]) shl 24);
  end;

  function GetUStringFromString(const AString: RawByteString; AIndex, ASize: Integer): String;
  begin
    result := '';
    if AIndex > Length(AString) - 1 then
      exit;

    SetLength(result, ASize);
    CopyMemory(@result[1], @AString[AIndex], ASize * 2);
  end;

var
  LTotalSize: Integer;
  i, m: Integer;
  LCurrentSize: Integer;
  LStr: String;
begin
  APairs.Clear;
  LTotalSize := GetInt32FromString(APairsRawData, 1);
  if LTotalSize + 4 <> Length(APairsRawData) then
    exit;

  i := 5;
  while true do
  begin
    LCurrentSize := GetInt32FromString(APairsRawData, i);
    i := i + 4;
    LStr := GetUStringFromString(APairsRawData, i, LCurrentSize);
    APairs.Add(LStr);
    i := i + LCurrentSize * 2;
    if i >= LTotalSize then
      break;

    m := (i - 1) mod 4;
    if m > 0 then
      i := i + (4 - m);
  end;
end;

{ TLoginData }

constructor TLoginData.Create;
begin
  FPairs := TStringList.Create;
end;

destructor TLoginData.Destroy;
begin
  FPairs.Free;
  inherited;
end;

end.
