unit wwSource;
{ Источник карт для ходилки: либо основное хранилище — граф в JSON, из
  которого карта строится заново геометрией на R, либо тестовая выгрузка
  CSV, то есть готовый снимок той же карты. }

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils, Contnrs, wwCore, wwGrid, wwStruct, wwCsv, wwJson, wwRGeom, wwRebuild;

type
  TWwMapSource = class
  public
    function LevelCount: Integer; virtual; abstract;
    function LoadGrid(ANumber: Integer): TWwGrid; virtual; abstract;
    function StairUpX(ANumber: Integer): Integer; virtual; abstract;
    function StairUpY(ANumber: Integer): Integer; virtual; abstract;
    function StairDownX(ANumber: Integer): Integer; virtual; abstract;
    function StairDownY(ANumber: Integer): Integer; virtual; abstract;
    function Describe: string; virtual; abstract;
  end;

  TWwCsvSource = class(TWwMapSource)
  private
    FReader: TWwCsvReader;
    FDir: string;
  public
    constructor Create(const ADir: string);
    destructor Destroy; override;
    function LevelCount: Integer; override;
    function LoadGrid(ANumber: Integer): TWwGrid; override;
    function StairUpX(ANumber: Integer): Integer; override;
    function StairUpY(ANumber: Integer): Integer; override;
    function StairDownX(ANumber: Integer): Integer; override;
    function StairDownY(ANumber: Integer): Integer; override;
    function Describe: string; override;
  end;

  TWwJsonSource = class(TWwMapSource)
  private
    FReader: TWwJsonReader;
    FGeom: TWwGeometryClient;
    FRebuilder: TWwRebuilder;
    FCache: TFPObjectList;
    FFile: string;
    function LevelObject(ANumber: Integer): TWwLevel;
  public
    constructor Create(const AFileName, AGeometryScript: string; const AEngine: string = '');
    destructor Destroy; override;
    function LevelCount: Integer; override;
    function LoadGrid(ANumber: Integer): TWwGrid; override;
    function StairUpX(ANumber: Integer): Integer; override;
    function StairUpY(ANumber: Integer): Integer; override;
    function StairDownX(ANumber: Integer): Integer; override;
    function StairDownY(ANumber: Integer): Integer; override;
    function Describe: string; override;
  end;

implementation

{ TWwCsvSource }

constructor TWwCsvSource.Create(const ADir: string);
begin
  inherited Create;
  FDir := ADir;
  FReader := TWwCsvReader.Create(ADir);
end;

destructor TWwCsvSource.Destroy;
begin
  FReader.Free;
  inherited Destroy;
end;

function TWwCsvSource.LevelCount: Integer;
begin
  Result := FReader.LevelCount;
end;

function TWwCsvSource.LoadGrid(ANumber: Integer): TWwGrid;
begin
  Result := FReader.LoadGrid(ANumber);
end;

function TWwCsvSource.StairUpX(ANumber: Integer): Integer;
begin
  Result := FReader.StairUpX(ANumber);
end;

function TWwCsvSource.StairUpY(ANumber: Integer): Integer;
begin
  Result := FReader.StairUpY(ANumber);
end;

function TWwCsvSource.StairDownX(ANumber: Integer): Integer;
begin
  Result := FReader.StairDownX(ANumber);
end;

function TWwCsvSource.StairDownY(ANumber: Integer): Integer;
begin
  Result := FReader.StairDownY(ANumber);
end;

function TWwCsvSource.Describe: string;
begin
  Result := Format('тестовая выгрузка CSV: %s', [FDir]);
end;

{ TWwJsonSource }

constructor TWwJsonSource.Create(const AFileName, AGeometryScript: string; const AEngine: string = '');
var
  i: Integer;
  lv: TWwLevel;
begin
  inherited Create;
  FFile := AFileName;
  FReader := TWwJsonReader.Create(AFileName);
  FGeom := TWwGeometryClient.Create(AGeometryScript, AEngine);
  FRebuilder := TWwRebuilder.Create(FGeom);
  FCache := TFPObjectList.Create(True);
  for i := 0 to FReader.LevelCount - 1 do
  begin
    lv := FReader.LevelAt(i);
    FRebuilder.Rebuild(lv);
    FCache.Add(lv);
  end;
end;

destructor TWwJsonSource.Destroy;
begin
  FCache.Free;
  FRebuilder.Free;
  FGeom.Free;
  FReader.Free;
  inherited Destroy;
end;

function TWwJsonSource.LevelObject(ANumber: Integer): TWwLevel;
var
  i: Integer;
begin
  for i := 0 to FCache.Count - 1 do
    if TWwLevel(FCache[i]).Number = ANumber then
    begin
      Result := TWwLevel(FCache[i]);
      Exit;
    end;
  Result := nil;
end;

function TWwJsonSource.LevelCount: Integer;
begin
  Result := FCache.Count;
end;

{ Ходилка владеет полученной сеткой, поэтому отдаём копию. }
function TWwJsonSource.LoadGrid(ANumber: Integer): TWwGrid;
var
  lv: TWwLevel;
begin
  Result := nil;
  lv := LevelObject(ANumber);
  if lv = nil then Exit;
  Result := lv.Grid.CopyRegion(0, 0, lv.Grid.W - 1, lv.Grid.H - 1);
end;

function TWwJsonSource.StairUpX(ANumber: Integer): Integer;
var
  lv: TWwLevel;
begin
  lv := LevelObject(ANumber);
  if lv = nil then Result := 1 else Result := lv.StairUpX;
end;

function TWwJsonSource.StairUpY(ANumber: Integer): Integer;
var
  lv: TWwLevel;
begin
  lv := LevelObject(ANumber);
  if lv = nil then Result := 1 else Result := lv.StairUpY;
end;

function TWwJsonSource.StairDownX(ANumber: Integer): Integer;
var
  lv: TWwLevel;
begin
  lv := LevelObject(ANumber);
  if lv = nil then Result := 1 else Result := lv.StairDownX;
end;

function TWwJsonSource.StairDownY(ANumber: Integer): Integer;
var
  lv: TWwLevel;
begin
  lv := LevelObject(ANumber);
  if lv = nil then Result := 1 else Result := lv.StairDownY;
end;

function TWwJsonSource.Describe: string;
begin
  Result := Format('граф из JSON: %s (карта построена геометрией на R)', [FFile]);
end;

end.
