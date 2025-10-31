unit SQLiteTable3;

{
  Simple classes for using SQLite's exec and get_table.

  TSQLiteDatabase wraps the calls to open and close an SQLite database.
  It also wraps SQLite_exec for queries that do not return a result set

  TSQLiteTable wraps sqlite_get_table.
  It allows accessing fields by name as well as index and can step through a
  result set with the Next procedure.

  Adapted by Tim Anderson (tim@itwriting.com)
  Originally created by Pablo Pissanetzky (pablo@myhtpc.net)
  Modified and enhanced by Lukas Gebauer
}

interface

uses
  Windows, SQLite3, Classes, SysUtils, StrUtils, WideStrUtils, AnsiStrings;

const

  dtInt = 1;
  dtNumeric = 2;
  dtStr = 3;
  dtBlob = 4;
  dtNull = 5;

type

  ESQLiteException = class(Exception)
  end;

  TSQLiteTable = class;

  TSQLiteDatabase = class
  private
    fDB: TSQLiteDB;
    fInTrans: boolean;
    procedure RaiseError(const s: String; SQL: UTF8String);
  public
    constructor Create(const FileName: UTF8String);
    destructor Destroy; override;
//    function GetTable(const SQL: UTF8String): TSQLiteTable; overload;
    function GetTable(const SQL: String): TSQLiteTable; overload;
    procedure ExecSQL(const SQL: UTF8String); overload;
    procedure ExecSQL(const SQL: String); overload;
    procedure UpdateBlob(const SQL: UTF8String; BlobData: TStream);
    procedure BeginTransaction;
    procedure Commit;
    procedure Rollback;
    function TableExists(const TableName: String): boolean;
    function GetLastInsertRowID: int64;
    procedure SetTimeout(Value: integer);
    function version: AnsiString;
  {published}
    property isTransactionOpen: boolean read fInTrans;

    function PrepareUTF8(SQL: UTF8String; var stmt: TSQLiteStmt): Integer;
    function Prepare(const SQL: String; var stmt: TSQLiteStmt): Integer;
    function Step(var stmt: TSQLiteStmt): Integer;
    procedure Finalize(var stmt: TSQLiteStmt);

    function BindNull(var stmt: TSQLiteStmt; index: Integer): Integer;
    function BindInt(var stmt: TSQLiteStmt; index: Integer; value: Integer): Integer; overload;
    function BindInt(var stmt: TSQLiteStmt; index: Integer; value: Boolean): Integer; overload;
    function BindInt64(var stmt: TSQLiteStmt; index: Integer; value: Int64): Integer;
    function BindText(var stmt: TSQLiteStmt; index: Integer; const value: String): Integer;
//    function BindText(var stmt: TSQLiteStmt; index: Integer; value: AnsiString): Integer; overload;
//    function BindText(var stmt: TSQLiteStmt; index: Integer; value: String): Integer; overload;
    function BindTextUTF8(var stmt: TSQLiteStmt; index: Integer; const value: UTF8String): Integer;
    function BindFloat(var stmt: TSQLiteStmt; index: Integer; value: Extended): Integer;
    function BindTextAnsi(var stmt: TSQLiteStmt; index: Integer; const value: AnsiString): Integer;

    function BindBlob(var stmt: TSQLiteStmt; index: Integer; ptr: Pointer; size: Integer): Integer;

    function ErrorMessage: pAnsichar;
  end;

  TSQLiteTable = class
  private
    fResults: TList;
    fRowCount: cardinal;
    fColCount: cardinal;
    fCols: TStringList;
    fColTypes: TList;
    fRow: cardinal;
    function GetFields(I: cardinal): AnsiString;
    function GetEOF: boolean;
    function GetBOF: boolean;
    function GetColumns(I: integer): String;
    function GetFieldByName(FieldName: String): UTF8String;
    function GetFieldIndex(FieldName: String): integer;
    function GetCount: integer;
    function GetCountResult: integer;
  public
    constructor Create(DB: TSQLiteDatabase; const SQL: UTF8String);
    destructor Destroy; override;
    function FieldAsInteger(I: cardinal): int64;
    function FieldAsBoolean(I: cardinal): Boolean;
    function FieldAsBlob(I: cardinal): TMemoryStream;
    function FieldAsBlobText(I: cardinal): AnsiString;
    function FieldIsNull(I: cardinal): boolean;
    function FieldAsString(I: cardinal): String;
    function FieldAsStringUTF8(I: cardinal): UTF8String;
    function FieldAsDouble(I: cardinal): double;
    function Next: boolean;
    function Previous: boolean;
    property EOF: boolean read GetEOF;
    property BOF: boolean read GetBOF;
    property Fields[I: cardinal]: AnsiString read GetFields;
    property FieldByName[FieldName: String]: UTF8String read GetFieldByName;
    property FieldIndex[FieldName: String]: integer read GetFieldIndex;
    property Columns[I: integer]: String read GetColumns;
    property ColCount: cardinal read fColCount;
    property RowCount: cardinal read fRowCount;
    property Row: cardinal read fRow;
    function MoveFirst: boolean;
    function MoveLast: boolean;
    property Count: integer read GetCount;
    // The property CountResult is used when you execute count(*) queries.
    // It returns 0 if the result set is empty or the value of the
    // first field as an integer.
    property CountResult: integer read GetCountResult;

    function ByNameAsString(const FieldName: String): String;
    function ByNameAsInteger(const FieldName: String): Int64;
    function ByNameAsDouble(const FieldName: String): Double;
    function ByNameIsNull(const FieldName: String): Boolean;
    function ByNameAsBoolean(const FieldName: String): Boolean;
    function ByNameAsStringUTF8(const FieldName: String): UTF8String;
    function ByNameAsBlobString(const FieldName: String): RawByteString;
  end;

procedure DisposePointer(ptr: pointer); cdecl;

implementation

procedure DisposePointer(ptr: pointer); cdecl;
begin
  if assigned(ptr) then
    freemem(ptr);
end;

//------------------------------------------------------------------------------
// TSQLiteDatabase
//------------------------------------------------------------------------------

function TSQLiteDatabase.ErrorMessage: pAnsichar;
begin
  result := sqlite3_errmsg(self.fDB);
end;

procedure TSQLiteDatabase.ExecSQL(const SQL: String);
begin
  ExecSQL(UTF8Encode(SQL));
end;

function TSQLiteDatabase.BindNull(var stmt: TSQLiteStmt; index: Integer): Integer;
begin
  result := SQLite3_BindNull(stmt,index);
end;

function TSQLiteDatabase.BindInt(var stmt: TSQLiteStmt; index: Integer; value: Integer): Integer;
begin
  result := SQLite3_BindInt(stmt,index,value);
end;

function TSQLiteDatabase.BindInt(var stmt: TSQLiteStmt; index: Integer; value: Boolean): Integer;
begin
  if value = true then
    result := SQLite3_BindInt(stmt,index,1)
  else
    result := SQLite3_BindInt(stmt,index,0);
end;

function TSQLiteDatabase.BindInt64(var stmt: TSQLiteStmt; index: Integer;
  value: Int64): Integer;
begin
  result := SQLite3_BindInt64(stmt,index,value);
end;

function TSQLiteDatabase.BindText(var stmt: TSQLiteStmt; index: Integer; const value: String): Integer;
begin
  result := SQLite3_BindText(stmt,index,pAnsichar(UTF8Encode(value)), -1, Pointer(SQLITE_TRANSIENT));
end;

function TSQLiteDatabase.BindTextUTF8(var stmt: TSQLiteStmt; index: Integer; const value: UTF8String): Integer;
begin
  result := SQLite3_BindText(stmt,index,pAnsichar(value), -1, Pointer(SQLITE_TRANSIENT));
end;

function TSQLiteDatabase.BindTextAnsi(var stmt: TSQLiteStmt; index: Integer; const value: AnsiString): Integer;
begin
  result := SQLite3_BindText(stmt,index,pAnsichar(value), -1, Pointer(SQLITE_TRANSIENT));
end;

{function TSQLiteDatabase.BindText(var stmt: TSQLiteStmt; index: Integer; value: AnsiString): Integer;
begin
  result := SQLite3_BindText(stmt,index,pAnsichar(value), -1, Pointer(SQLITE_TRANSIENT));
end;}

{function TSQLiteDatabase.BindText(var stmt: TSQLiteStmt; index: Integer; value: String): Integer;
begin
  result := SQLite3_BindText(stmt,index,pAnsichar(AnsiString(value)), -1, nil);
end;}

function TSQLiteDatabase.BindBlob(var stmt: TSQLiteStmt; index: Integer;
  ptr: Pointer; size: Integer): Integer;
begin
  result := SQLite3_BindBlob(stmt, index, ptr, size, Pointer(SQLITE_TRANSIENT));
end;

function TSQLiteDatabase.BindFloat(var stmt: TSQLiteStmt; index: Integer; value: Extended): Integer;
begin
  result := SQLite3_BindFloat(stmt,index,value);
end;

function TSQLiteDatabase.PrepareUTF8(SQL: UTF8String; var stmt: TSQLiteStmt): Integer;
var
  NextSQLStatement: PAnsichar;
begin
  result := Sqlite3_Prepare(self.fDB, Pointer(SQL), -1, Stmt, NextSQLStatement);
end;

function TSQLiteDatabase.Prepare(const SQL: String; var stmt: TSQLiteStmt): Integer;
var
  NextSQLStatement: PAnsichar;
begin
  result := Sqlite3_Prepare(self.fDB, Pointer(UTF8Encode(SQL)), -1, Stmt, NextSQLStatement);
end;

function TSQLiteDatabase.Step(var stmt: TSQLiteStmt): Integer;
begin
  result := Sqlite3_step(stmt);
end;

procedure TSQLiteDatabase.Finalize(var stmt: TSQLiteStmt);
begin
  Sqlite3_Finalize(stmt);
end;

constructor TSQLiteDatabase.Create(const FileName: UTF8String);
var
  Msg: pAnsichar;
  iResult: integer;
begin
  inherited Create;

  self.fInTrans := False;

  Msg := nil;
  try
    iResult := SQLite3_Open(Pointer(FileName), Fdb);

    if iResult <> SQLITE_OK then
      if Assigned(Fdb) then
      begin
        Msg := Sqlite3_ErrMsg(Fdb);
        raise ESqliteException.CreateFmt('Failed to open database "%s" : %s',
          [FileName, Msg]);
      end
      else
        raise ESqliteException.CreateFmt('Failed to open database "%s" : unknown error',
          [FileName]);

    //set a few configs
//    self.ExecSQL('PRAGMA SYNCHRONOUS=OFF;');
//    self.ExecSQL('PRAGMA full_column_names = 1;');
//    self.ExecSQL('PRAGMA temp_store = MEMORY;');

  finally
    if Assigned(Msg) then
      SQLite3_Free(Msg);
  end;
end;


//..............................................................................

destructor TSQLiteDatabase.Destroy;
begin

  if self.fInTrans then
    self.ExecSQL('ROLLBACK;'); //assume rollback

  if Assigned(fDB) then
    SQLite3_Close(fDB);

  inherited;
end;

function TSQLiteDatabase.GetLastInsertRowID: int64;
begin
  Result := Sqlite3_LastInsertRowID(self.fDB);
end;

//..............................................................................

procedure TSQLiteDatabase.RaiseError(const s: String; SQL: UTF8String);
//look up last error and raise an exception with an appropriate message
var
  Msg: PAnsiChar;
  str: String;
begin

  Msg := nil;

  if sqlite3_errcode(self.fDB) <> SQLITE_OK then
    Msg := sqlite3_errmsg(self.fDB);

  if Msg <> nil then
  begin
    str := UTF8ToString(sqlite3_errmsg(self.fDB));
    raise ESqliteException.CreateFmt(s + ' "%s" : %s', [UTF8TOString(SQL), str])
  end
  else
    raise ESqliteException.CreateFmt(s, [UTF8TOString(SQL), 'No message']);

end;

procedure TSQLiteDatabase.ExecSQL(const SQL: UTF8String);
var
  Stmt: TSQLiteStmt;
  NextSQLStatement: PAnsichar;
  iStepResult: integer;
begin
  try

    iStepResult := Sqlite3_Prepare(self.fDB, Pointer(SQL), -1, Stmt, NextSQLStatement);

    if iStepResult <> SQLITE_OK then
      RaiseError('Error executing SQL ' + IntToStr(iStepResult), SQL);

    if (Stmt = nil) then
      RaiseError('Could not prepare SQL statement', SQL);

    iStepResult := Sqlite3_step(Stmt);

    if (iStepResult <> SQLITE_DONE) then
      RaiseError('Error executing SQL statement', SQL);

  finally

    if Assigned(Stmt) then
      Sqlite3_Finalize(stmt);

  end;
end;

procedure TSQLiteDatabase.UpdateBlob(const SQL: UTF8String; BlobData: TStream);
var
  iSize: integer;
  ptr: pointer;
  Stmt: TSQLiteStmt;
  Msg: PAnsichar;
  NextSQLStatement: PAnsichar;
  iStepResult: integer;
  iBindResult: integer;
begin
  //expects SQL of the form 'UPDATE MYTABLE SET MYFIELD = ? WHERE MYKEY = 1'

  if Pos('?', UTF8ToString(SQL)) = 0 then
    RaiseError('SQL must include a ? parameter', SQL);

  Msg := nil;
  try

    if Sqlite3_Prepare(self.fDB, PAnsiChar(SQL), -1, Stmt, NextSQLStatement) <>
      SQLITE_OK then
      RaiseError('Could not prepare SQL statement', SQL);

    if (Stmt = nil) then
      RaiseError('Could not prepare SQL statement', SQL);

    //now bind the blob data
    iSize := BlobData.size;

    GetMem(ptr, iSize);

    if (ptr = nil) then
      raise ESqliteException.CreateFmt('Error getting memory to save blob',
        [SQL, 'Error']);

    BlobData.position := 0;
    BlobData.Read(ptr^, iSize);

    iBindResult := SQLite3_BindBlob(stmt, 1, ptr, iSize, @DisposePointer);

    if iBindResult <> SQLITE_OK then
      RaiseError('Error binding blob to database', SQL);

    iStepResult := Sqlite3_step(Stmt);

    if (iStepResult <> SQLITE_DONE) then
      RaiseError('Error executing SQL statement', SQL);

  finally

    if Assigned(Stmt) then
      Sqlite3_Finalize(stmt);

    if Assigned(Msg) then
      SQLite3_Free(Msg);
  end;

end;

//..............................................................................

function TSQLiteDatabase.GetTable(const SQL: String): TSQLiteTable;
begin
  Result := TSQLiteTable.Create(Self, UTF8Encode(SQL));
end;

procedure TSQLiteDatabase.BeginTransaction;
begin
  if not self.fInTrans then
  begin
    self.ExecSQL('BEGIN TRANSACTION;');
    self.fInTrans := True;
  end
  else
    raise ESqliteException.Create('Transaction already open');
end;

procedure TSQLiteDatabase.Commit;
begin
  self.ExecSQL('COMMIT;');
  self.fInTrans := False;
end;

procedure TSQLiteDatabase.Rollback;
begin
  self.ExecSQL('ROLLBACK;');
  self.fInTrans := False;
end;

function TSQLiteDatabase.TableExists(const TableName: String): boolean;
var
  sql: String;
  ds: TSqliteTable;
begin
  sql := 'select [sql] from sqlite_master where [type] = ''table'' and name = ''' +
    TableName + ''' ';

  ds := self.GetTable(sql);
  try
    Result := (ds.Count > 0);
  finally
    FreeAndNil(ds);
  end;
end;

procedure TSQLiteDatabase.SetTimeout(Value: integer);
begin
  SQLite3_BusyTimeout(self.fDB, Value);
end;

function TSQLiteDatabase.version: AnsiString;
begin
  Result := SQLite3_Version;
end;


//------------------------------------------------------------------------------
// TSQLiteTable
//------------------------------------------------------------------------------

function TSQLiteTable.ByNameAsDouble(const FieldName: String): Double;
begin
  result := FieldAsDouble(FieldIndex[FieldName]);
end;

function TSQLiteTable.ByNameAsInteger(const FieldName: String): Int64;
begin
  result := FieldAsInteger(FieldIndex[FieldName]);
end;

function TSQLiteTable.ByNameAsBlobString(const FieldName: String): RawByteString;
begin
  result := FieldAsBlobText(FieldIndex[FieldName]);
end;

function TSQLiteTable.ByNameAsBoolean(const FieldName: String): Boolean;
begin
  result := FieldAsBoolean(FieldIndex[FieldName]);
end;

function TSQLiteTable.ByNameAsString(const FieldName: String): String;
begin
//  result := UTF8Decode(FieldAsString(FieldIndex[FieldName]));
  result := FieldAsString(FieldIndex[FieldName]);
end;

function TSQLiteTable.ByNameAsStringUTF8(const FieldName: String): UTF8String;
begin
  result := FieldAsStringUTF8(FieldIndex[FieldName]);
end;

function TSQLiteTable.ByNameIsNull(const FieldName: String): Boolean;
begin
  result := FieldIsNull(FieldIndex[FieldName]);
end;

constructor TSQLiteTable.Create(DB: TSQLiteDatabase; const SQL: UTF8String);
var
  Stmt: TSQLiteStmt;
  NextSQLStatement: PAnsichar;
  iStepResult: integer;
  ptr: pointer;
  iNumBytes: integer;
  thisBlobValue: TMemoryStream;
  thisStringValue: pansistring;
  thisDoubleValue: pDouble;
  thisIntValue: pInt64;
  thisColType: pInteger;
  i: integer;
  DeclaredColType: PAnsichar;
  ActualColType: integer;
  ptrValue: PAnsichar;
begin
  try
    self.fRowCount := 0;
    self.fColCount := 0;
    //if there are several SQL statements in SQL, NextSQLStatment points to the
    //beginning of the next one. Prepare only prepares the first SQL statement.
    if Sqlite3_Prepare(DB.fDB, Pointer(SQL), -1, Stmt, NextSQLStatement) <> SQLITE_OK then
      DB.RaiseError('Error executing SQL', SQL);
    if (Stmt = nil) then
      DB.RaiseError('Could not prepare SQL statement', SQL);
    iStepResult := Sqlite3_step(Stmt);
    while (iStepResult <> SQLITE_DONE) do
    begin
      case iStepResult of
        SQLITE_ROW:
          begin
            Inc(fRowCount);
            if (fRowCount = 1) then
            begin
            //get data types
              fCols := TStringList.Create;
              fColTypes := TList.Create;
              fColCount := SQLite3_ColumnCount(stmt);
              for i := 0 to Pred(fColCount) do
                fCols.Add(UTF8ToString(Sqlite3_ColumnName(stmt, i)));
              for i := 0 to Pred(fColCount) do
              begin
                new(thisColType);
                DeclaredColType := Sqlite3_ColumnDeclType(stmt, i);
                if DeclaredColType = nil then
                  thisColType^ := Sqlite3_ColumnType(stmt, i) //use the actual column type instead
                //seems to be needed for last_insert_rowid
                else
                  if (DeclaredColType = 'INTEGER') or (DeclaredColType = 'BOOLEAN') then
                    thisColType^ := dtInt
                  else
                    if (DeclaredColType = 'NUMERIC') or
                      (DeclaredColType = 'FLOAT') or
                      (DeclaredColType = 'DOUBLE') or
                      (DeclaredColType = 'REAL') then
                      thisColType^ := dtNumeric
                    else
                      if DeclaredColType = 'BLOB' then
                        thisColType^ := dtBlob
                      else
                        thisColType^ := dtStr;
                fColTypes.Add(thiscoltype);
              end;
              fResults := TList.Create;
            end;

          //get column values
            for i := 0 to Pred(ColCount) do
            begin
              ActualColType := Sqlite3_ColumnType(stmt, i);
              if (ActualColType = SQLITE_NULL) then
                fResults.Add(nil)
              else
                if pInteger(fColTypes[i])^ = dtInt then
                begin
                  new(thisintvalue);
                  thisintvalue^ := Sqlite3_ColumnInt64(stmt, i);
                  fResults.Add(thisintvalue);
                end
                else
                  if pInteger(fColTypes[i])^ = dtNumeric then
                  begin
                    new(thisdoublevalue);
                    thisdoublevalue^ := Sqlite3_ColumnDouble(stmt, i);
                    fResults.Add(thisdoublevalue);
                  end
                  else
                    if pInteger(fColTypes[i])^ = dtBlob then
                    begin
                      iNumBytes := Sqlite3_ColumnBytes(stmt, i);
                      if iNumBytes = 0 then
                        thisblobvalue := nil
                      else
                      begin
                        thisblobvalue := TMemoryStream.Create;
                        thisblobvalue.position := 0;
                        ptr := Sqlite3_ColumnBlob(stmt, i);
                        thisblobvalue.writebuffer(ptr^, iNumBytes);
                      end;
                      fResults.Add(thisblobvalue);
                    end
                    else
                    begin
                      new(thisstringvalue);
                      ptrValue := Sqlite3_ColumnText(stmt, i);
                      setstring(thisstringvalue^, ptrvalue, AnsiStrings.strlen(ptrvalue));
                      fResults.Add(thisstringvalue);
                    end;
            end;
          end;
        SQLITE_BUSY:
          raise ESqliteException.CreateFmt('Could not prepare SQL statement',
            [SQL, 'SQLite is Busy']);
      else
        DB.RaiseError('Could not retrieve data', SQL);
      end;
      iStepResult := Sqlite3_step(Stmt);
    end;
    fRow := 0;
  finally
    if Assigned(Stmt) then
      Sqlite3_Finalize(stmt);
  end;
end;

//..............................................................................

destructor TSQLiteTable.Destroy;
var
  i: cardinal;
  iColNo: integer;
begin
  if Assigned(fResults) then
  begin
    for i := 0 to fResults.Count - 1 do
    begin
      //check for blob type
      iColNo := (i mod fColCount);
      case pInteger(self.fColTypes[iColNo])^ of
        dtBlob:
          TMemoryStream(fResults[i]).Free;
        dtStr:
          if fResults[i] <> nil then
          begin
            setstring(string(fResults[i]^), nil, 0);
            dispose(fResults[i]);
          end;
      else
        dispose(fResults[i]);
      end;
    end;
    FreeAndNil(fResults);
  end;
  if Assigned(fCols) then
    FreeAndNil(fCols);
  if Assigned(fColTypes) then
    for i := 0 to fColTypes.Count - 1 do
      dispose(fColTypes[i]);
  FreeAndNil(fColTypes);
  inherited;
end;

//..............................................................................

function TSQLiteTable.GetColumns(I: integer): String;
begin
  Result := fCols[I];
end;

//..............................................................................

function TSQLiteTable.GetCountResult: integer;
begin
  if not EOF then
    Result := StrToIntDef(String(Fields[0]), 0)
  else
    Result := 0;
end;

function TSQLiteTable.GetCount: integer;
begin
  Result := FRowCount;
end;

//..............................................................................

function TSQLiteTable.GetEOF: boolean;
begin
  Result := fRow >= fRowCount;
end;

function TSQLiteTable.GetBOF: boolean;
begin
  Result := fRow <= 0;
end;

//..............................................................................

function TSQLiteTable.GetFieldByName(FieldName: String): UTF8String;
begin
  Result := UTF8String(GetFields(self.GetFieldIndex(FieldName)));
end;

function TSQLiteTable.GetFieldIndex(FieldName: String): integer;
begin
  if (fCols = nil) then
  begin
    raise ESqliteException.Create('Field ' + fieldname + ' Not found. Empty dataset');
    exit;
  end;

  if (fCols.count = 0) then
  begin
    raise ESqliteException.Create('Field ' + fieldname + ' Not found. Empty dataset');
    exit;
  end;

  //Result := fCols.IndexOf(UTF8UpperCase(fname));
  Result := fCols.IndexOf(FieldName);

  if (result < 0) then
  begin raise ESqliteException.Create('Field not found in dataset: ' + fieldname) end;

end;

//..............................................................................

function TSQLiteTable.GetFields(I: cardinal): AnsiString;
var
  thisvalue: pansistring;
  thistype: integer;
begin
  Result := '';
  if EOF then
    raise ESqliteException.Create('Table is at End of File');
  //integer types are not stored in the resultset
  //as strings, so they should be retrieved using the type-specific
  //methods
  thistype := pInteger(self.fColTypes[I])^;

  case thistype of
    dtStr:
      begin
        thisvalue := self.fResults[(self.frow * self.fColCount) + I];
        if (thisvalue <> nil) then
          Result := thisvalue^
        else
          Result := '';
      end;
    dtInt:
      Result := AnsiString(IntToStr(self.FieldAsInteger(I)));
    dtNumeric:
      Result := AnsiString(FloatToStr(self.FieldAsDouble(I)));
    dtBlob:
      Result := self.FieldAsBlobText(I);
  else
    Result := '';
  end;
end;

function TSqliteTable.FieldAsBlob(I: cardinal): TMemoryStream;
begin
  if EOF then
    raise ESqliteException.Create('Table is at End of File');
  if (self.fResults[(self.frow * self.fColCount) + I] = nil) then
    Result := nil
  else
    if pInteger(self.fColTypes[I])^ = dtBlob then
      Result := TMemoryStream(self.fResults[(self.frow * self.fColCount) + I])
    else
      raise ESqliteException.Create('Not a Blob field');
end;

function TSqliteTable.FieldAsBlobText(I: cardinal): AnsiString;
var
  MemStream: TMemoryStream;
  Buffer: PAnsiChar;
begin
  Result := '';
  MemStream := self.FieldAsBlob(I);
  if MemStream <> nil then
    if MemStream.Size > 0 then
    begin
      MemStream.position := 0;
      Buffer := AnsiStrings.AnsiStrAlloc(MemStream.Size + 1);
      MemStream.readbuffer(Buffer[0], MemStream.Size);
      (Buffer + MemStream.Size)^ := chr(0);
      SetString(Result, Buffer, MemStream.size);
      AnsiStrings.strdispose(Buffer);
    end;
end;


function TSqliteTable.FieldAsInteger(I: cardinal): int64;
begin
  if EOF then
    raise ESqliteException.Create('Table is at End of File');
  if (self.fResults[(self.frow * self.fColCount) + I] = nil) then
    Result := 0
  else
  case pInteger(self.fColTypes[I])^ of
  dtInt:
    Result := pInt64(self.fResults[(self.frow * self.fColCount) + I])^;
  dtNumeric:
    Result := trunc(strtofloat(pString(self.fResults[(self.frow * self.fColCount) + I])^));
  dtNull:
    Result := 0;
  dtStr:
    result := StrToIntDef(FieldAsString(i),0);
  else
    raise ESqliteException.Create('Not an integer or numeric field');
  end;
end;

function TSqliteTable.FieldAsBoolean(I: cardinal): Boolean;
begin
  if EOF then
    raise ESqliteException.Create('Table is at End of File');
  if (self.fResults[(self.frow * self.fColCount) + I] = nil) then
    Result := false
  else
  case pInteger(self.fColTypes[I])^ of
  dtInt, dtNumeric:
    Result := pInt64(self.fResults[(self.frow * self.fColCount) + I])^ > 0;
  dtNull:
    Result := false;
  dtStr:
    result := FieldAsString(i) <> '';
  else
    raise ESqliteException.Create('Not an boolean field');
  end;
end;

function TSqliteTable.FieldAsDouble(I: cardinal): double;
begin
  if EOF then
    raise ESqliteException.Create('Table is at End of File');
  if (self.fResults[(self.frow * self.fColCount) + I] = nil) then
    Result := 0
  else
    if pInteger(self.fColTypes[I])^ = dtInt then
      Result := pInt64(self.fResults[(self.frow * self.fColCount) + I])^
    else
      if pInteger(self.fColTypes[I])^ = dtNumeric then
        Result := pDouble(self.fResults[(self.frow * self.fColCount) + I])^
      else
        raise ESqliteException.Create('Not an integer or numeric field');
end;

function TSqliteTable.FieldAsString(I: cardinal): String;
var
  intvar: Int64;
begin
  if EOF then
    raise ESqliteException.Create('Table is at End of File');
  if (self.fResults[(self.frow * self.fColCount) + I] = nil) then
    Result := ''
  else
  case pInteger(self.fColTypes[I])^ of
  dtInt:
  begin
    intvar := pInt64(self.fResults[(self.frow * self.fColCount) + I])^;
    Result := IntToStr(intvar);
  end;
  dtNumeric:
  begin
    intvar := trunc(strtofloat(pString(self.fResults[(self.frow * self.fColCount) + I])^));
    Result := IntToStr(intvar);
  end;
  dtNull:
    Result := '';
  dtStr:
//    Result := String(self.GetFields(I));
    Result := UTF8ToString(self.GetFields(I));
  else
    Result := String(self.GetFields(I));
  end;
end;

function TSQLiteTable.FieldAsStringUTF8(I: cardinal): UTF8String;
var
  intvar: Int64;
begin
  if EOF then
    raise ESqliteException.Create('Table is at End of File');
  if (self.fResults[(self.frow * self.fColCount) + I] = nil) then
    Result := ''
  else
  case pInteger(self.fColTypes[I])^ of
  dtInt:
  begin
    intvar := pInt64(self.fResults[(self.frow * self.fColCount) + I])^;
    Result := UTF8Encode(IntToStr(intvar));
  end;
  dtNumeric:
  begin
    intvar := trunc(strtofloat(pString(self.fResults[(self.frow * self.fColCount) + I])^));
    Result := UTF8Encode(IntToStr(intvar));
  end;
  dtNull:
    Result := '';
  dtStr:
  begin
    result := RawByteString(self.GetFields(I));
  end
  else
    Result := UTF8String(self.GetFields(I));
  end;
end;

function TSqliteTable.FieldIsNull(I: cardinal): boolean;
var
  thisvalue: pointer;
begin
  if EOF then
    raise ESqliteException.Create('Table is at End of File');
  thisvalue := self.fResults[(self.frow * self.fColCount) + I];
  Result := (thisvalue = nil);
end;

//..............................................................................

function TSQLiteTable.Next: boolean;
begin
  Result := False;
  if not EOF then
  begin
    Inc(fRow);
    Result := True;
  end;
end;

function TSQLiteTable.Previous: boolean;
begin
  Result := False;
  if not BOF then
  begin
    Dec(fRow);
    Result := True;
  end;
end;

function TSQLiteTable.MoveFirst: boolean;
begin
  Result := False;
  if self.fRowCount > 0 then
  begin
    fRow := 0;
    Result := True;
  end;
end;

function TSQLiteTable.MoveLast: boolean;
begin
  Result := False;
  if self.fRowCount > 0 then
  begin
    fRow := fRowCount - 1;
    Result := True;
  end;
end;


end.

