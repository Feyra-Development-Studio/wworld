unit wwPaths;
{ Поиск ресурсов, которые после установки лежат не рядом с исходниками.

  В репозитории скрипты R лежат в scripts/, в пакете — в /usr/share/wworld,
  в архиве для Windows — рядом с exe. Программа не должна об этом знать:
  она спрашивает у TWwAssets путь и получает первый существующий. }

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils;

type
  TWwAssets = class
  private
    FExeDir: string;
    function FirstExisting(const ACandidates: array of string): string;
  public
    constructor Create;
    function Resolve(const APreferred, AFileName: string): string;
    property ExeDir: string read FExeDir;
  end;

implementation

constructor TWwAssets.Create;
begin
  inherited Create;
  FExeDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
end;

function TWwAssets.FirstExisting(const ACandidates: array of string): string;
var
  i: Integer;
begin
  for i := Low(ACandidates) to High(ACandidates) do
    if (ACandidates[i] <> '') and FileExists(ACandidates[i]) then
    begin
      Result := ACandidates[i];
      Exit;
    end;
  Result := '';
end;

{ Порядок: явно указанный путь, переменная окружения, каталог рядом с
  программой, системный каталог пакета, раскладка репозитория. Если ничего
  не нашлось — возвращаем то, что просили, чтобы сообщение об ошибке
  называло ожидаемый путь, а не пустую строку. }
function TWwAssets.Resolve(const APreferred, AFileName: string): string;
var
  found: string;
begin
  found := FirstExisting([
    APreferred,
    GetEnvironmentVariable('WWORLD_SHARE') + PathDelim + AFileName,
    FExeDir + AFileName,
    FExeDir + '..' + PathDelim + 'share' + PathDelim + 'wworld' + PathDelim + AFileName,
    '/usr/share/wworld/' + AFileName,
    '/usr/local/share/wworld/' + AFileName,
    'scripts' + PathDelim + AFileName
  ]);
  if found <> '' then Result := found else Result := APreferred;
end;

end.
