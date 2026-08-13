unit wwRGeom;
{ Клиент геометрического сервера на R.

  Генератор поднимает один процесс Rscript на всю генерацию и общается с
  ним построчно через каналы. Формы комнат (матрицы-маски), кисти коридоров
  и разворачивание осевой линии в вектор клеток считаются на R — здесь
  только транспорт, разбор ответа и кеш.

  Кеш нужен по делу: планировщик перебирает десятки вариантов размещения и
  переспрашивает одни и те же формы. Ответы сервера — чистые функции своих
  аргументов, поэтому запоминать их безопасно и на воспроизводимость это не
  влияет. }

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils, Classes, Process, Contnrs, wwCore, wwShapes;

type
  EWwGeometry = class(Exception);

  TWwGeometryClient = class
  private
    FProc: TProcess;
    FScript: string;
    FCache: TFPStringHashTable;
    FCalls, FHits: Integer;
    function ReadLine: string;
    function Ask(const ARequest: string; AUseCache: Boolean): string;
    function ShapeFromReply(const AName, AReply: string): TWwShape;
  public
    constructor Create(const AScriptPath: string);
    destructor Destroy; override;
    function Build(ASpec: TWwShapeSpec): TWwShape;
    procedure BrushOffsets(ARank: Integer; AOut: TWwPointList);
    procedure ExpandPath(ARank: Integer; APath, AOut: TWwPointList);
    property Calls: Integer read FCalls;
    property CacheHits: Integer read FHits;
  end;

implementation

constructor TWwGeometryClient.Create(const AScriptPath: string);
var
  reply: string;
begin
  inherited Create;
  FScript := AScriptPath;
  if not FileExists(FScript) then
    raise EWwGeometry.CreateFmt('не найден геометрический скрипт: %s', [FScript]);
  FCache := TFPStringHashTable.Create;
  FProc := TProcess.Create(nil);
  FProc.Executable := 'Rscript';
  FProc.Parameters.Add(FScript);
  FProc.Options := [poUsePipes, poStderrToOutPut];
  try
    FProc.Execute;
  except
    on E: Exception do
      raise EWwGeometry.CreateFmt('не удалось запустить Rscript: %s', [E.Message]);
  end;
  reply := Ask('PING', False);
  if reply <> 'OK PONG' then
    raise EWwGeometry.CreateFmt('геометрический сервер не отвечает: %s', [reply]);
end;

destructor TWwGeometryClient.Destroy;
var
  s: string;
begin
  if (FProc <> nil) and FProc.Running then
  begin
    s := 'QUIT' + LineEnding;
    try
      FProc.Input.Write(s[1], Length(s));
      FProc.WaitOnExit;
    except
      { сервер уже мёртв — гасим молча }
    end;
  end;
  FProc.Free;
  FCache.Free;
  inherited Destroy;
end;

function TWwGeometryClient.ReadLine: string;
var
  c: Char;
  n: Integer;
begin
  Result := '';
  repeat
    n := FProc.Output.Read(c, 1);
    if n = 0 then
      raise EWwGeometry.Create('геометрический сервер закрыл канал');
    if c = #10 then Exit;
    if c <> #13 then Result := Result + c;
  until False;
end;

function TWwGeometryClient.Ask(const ARequest: string; AUseCache: Boolean): string;
var
  line: string;
begin
  if AUseCache then
  begin
    Result := FCache[ARequest];
    if Result <> '' then
    begin
      Inc(FHits);
      Exit;
    end;
  end;
  line := ARequest + LineEnding;
  FProc.Input.Write(line[1], Length(line));
  Result := ReadLine;
  Inc(FCalls);
  if Copy(Result, 1, 3) = 'ERR' then
    raise EWwGeometry.CreateFmt('геометрия: %s (запрос: %s)', [Result, ARequest]);
  if AUseCache then FCache.Add(ARequest, Result);
end;

{ Ответ: OK W H METRIC <маска 0/1 по строкам> }
function TWwGeometryClient.ShapeFromReply(const AName, AReply: string): TWwShape;
var
  parts: TStringArray;
begin
  parts := AReply.Split([' ']);
  if Length(parts) < 5 then
    raise EWwGeometry.CreateFmt('плохой ответ геометрии: %s', [AReply]);
  Result := TWwShape.Create(AName, StrToInt(parts[1]), StrToInt(parts[2]),
    StrToInt(parts[3]), parts[4]);
end;

{ Форма строится по инструкции: спецификация сама знает, во что она
  разворачивается на стороне R. }
function TWwGeometryClient.Build(ASpec: TWwShapeSpec): TWwShape;
begin
  Result := ShapeFromReply(ASpec.ShapeName, Ask(ASpec.Request, True));
end;

procedure TWwGeometryClient.BrushOffsets(ARank: Integer; AOut: TWwPointList);
var
  parts: TStringArray;
  i, n: Integer;
begin
  AOut.Clear;
  parts := Ask(Format('BRUSH %d', [ARank]), True).Split([' ']);
  n := StrToInt(parts[1]);
  for i := 0 to n - 1 do
    AOut.Add(StrToInt(parts[2 + i * 2]), StrToInt(parts[3 + i * 2]));
end;

procedure TWwGeometryClient.ExpandPath(ARank: Integer; APath, AOut: TWwPointList);
var
  req: string;
  parts: TStringArray;
  i, n: Integer;
begin
  AOut.Clear;
  req := Format('EXPAND %d %d', [ARank, APath.Count]);
  for i := 0 to APath.Count - 1 do
    req := req + Format(' %d %d', [APath.X[i], APath.Y[i]]);
  parts := Ask(req, False).Split([' ']);
  n := StrToInt(parts[1]);
  for i := 0 to n - 1 do
    AOut.Add(StrToInt(parts[2 + i * 2]), StrToInt(parts[3 + i * 2]));
end;

end.
