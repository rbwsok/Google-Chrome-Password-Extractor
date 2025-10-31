program ChromePassword;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  Winapi.Windows,
  Winapi.ShlObj,
  SQLite3 in 'sqlite\SQLite3.pas',
  SQLiteTable3 in 'sqlite\SQLiteTable3.pas',
  GoogleChromePassword in 'GoogleChromePassword.pas';

var
  LBuffer: array [0..MAX_PATH - 1] of char;
  LBaseDirectory: String;
  LChromePasswordExtractor: TGoogleChromePasswordExtractor;

  i, j, k: Integer;
begin
  if ParamCount = 0 then
  begin
    writeln('parameters: <path from APPDATA>');
    writeln('  example1: "Google\Chrome\User Data\" - for Google Chrome');
    writeln('  example2: "Microsoft\Edge\User Data\" - for Microsoft Edge');
    writeln('  example3: "Vivaldi\User Data\" - for Vivaldi');
    writeln('  etc....');
    writeln('');
    writeln('  default - for chrome');
    writeln('');
  end;

  LChromePasswordExtractor := TGoogleChromePasswordExtractor.Create;
  try
    ShGetFolderPath(0, CSIDL_LOCAL_APPDATA, 0, 0, LBuffer);
    if ParamCount = 0 then
      LBaseDirectory := IncludeTrailingPathDelimiter(LBuffer) + 'Google\Chrome\User Data\'
      //LBaseDirectory := IncludeTrailingPathDelimiter(LBuffer) + 'Vivaldi\User Data\'
      //LBaseDirectory := IncludeTrailingPathDelimiter(LBuffer) + 'Microsoft\Edge\User Data\'
    else
      LBaseDirectory := IncludeTrailingPathDelimiter(LBuffer) + ParamStr(1);

    LChromePasswordExtractor.GetAllProfiles(LBaseDirectory);

    i := 0;
    while i < LChromePasswordExtractor.Profiles.Count do
    begin
      writeln('');
      writeln('=============================================');
      writeln('Profile Database: ' + LChromePasswordExtractor.Profiles[i]);
      writeln('');

      LChromePasswordExtractor.GetLogins(LBaseDirectory, LChromePasswordExtractor.Profiles[i]);

      for j := 0 to LChromePasswordExtractor.Logins.Count - 1 do
      begin
        writeln('----------------------------------');
        if LChromePasswordExtractor.Logins[j].ActionURL = '' then
          writeln('url: ' + LChromePasswordExtractor.Logins[j].OriginURL)
        else
          writeln('url: ' + LChromePasswordExtractor.Logins[j].ActionURL);

        writeln('login: ' + LChromePasswordExtractor.Logins[j].UserName);
        writeln('password: ' + LChromePasswordExtractor.Logins[j].Password);

        k := 0;
        while k < LChromePasswordExtractor.Logins[j].Pairs.Count do
        begin
          if k + 1 < LChromePasswordExtractor.Logins[j].Pairs.Count then
            writeln('string: ' + LChromePasswordExtractor.Logins[j].Pairs[k + 1] + ' - ' + LChromePasswordExtractor.Logins[j].Pairs[k]);
          inc(k, 2);
        end;
      end;
      inc(i);
    end;
  finally
    LChromePasswordExtractor.Free;
  end;
end.

