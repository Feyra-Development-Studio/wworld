unit wwCsv;
{ Экспорт подземелья в CSV. Каждый этаж — отдельный лист, то есть отдельный
  файл level_NN.csv (в CSV нет вкладок, поэтому лист = файл; index.csv
  играет роль оглавления книги).
  Рядом кладутся level_NN_owner.csv (матрица владельцев клеток) и общие
  таблицы rooms/corridors/links — по ним валидатор на R независимо
  проверяет связность и отсутствие наложений. }

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils, Classes, wwCore, wwGrid, wwStruct, wwShapes;

type
  TWwCsvWriter = class
  private
    FDir: string;
    FIndex, FRooms, FCorridors, FLinks: TStringList;
    function LevelFileName(ANumber: Integer; const ASuffix: string): string;
    procedure WriteMatrix(AGrid: TWwGrid; const AFileName: string; AOwners: Boolean);
  public
    constructor Create(const ADir: string);
    destructor Destroy; override;
    procedure AddLevel(ALevel: TWwLevel);
    procedure Flush;
  end;

  { Чтение выгруженных листов обратно — для ходилки и внешних инструментов. }
  TWwCsvReader = class
  private
    FDir: string;
    FIndex: TStringList;
    function Field(const ALine: string; AIndex: Integer): string;
  public
    constructor Create(const ADir: string);
    destructor Destroy; override;
    function LevelCount: Integer;
    function LoadGrid(ANumber: Integer): TWwGrid;
    function StairUpX(ANumber: Integer): Integer;
    function StairUpY(ANumber: Integer): Integer;
    function StairDownX(ANumber: Integer): Integer;
    function StairDownY(ANumber: Integer): Integer;
  end;

implementation

constructor TWwCsvWriter.Create(const ADir: string);
begin
  inherited Create;
  FDir := IncludeTrailingPathDelimiter(ADir);
  if not DirectoryExists(FDir) then ForceDirectories(FDir);
  FIndex := TStringList.Create;
  FRooms := TStringList.Create;
  FCorridors := TStringList.Create;
  FLinks := TStringList.Create;
  FIndex.Add('level,sheet,owner_sheet,width,height,seed,rooms,corridors,forks,links,' +
             'stair_up_x,stair_up_y,stair_down_x,stair_down_y');
  FRooms.Add('level,id,kind,shape,x0,y0,w,h,size_metric,cells');
  FCorridors.Add('level,id,rank,rank_name,from_id,to_id,path_len,cells');
  FLinks.Add('level,a,b,kind');
end;

destructor TWwCsvWriter.Destroy;
begin
  FIndex.Free;
  FRooms.Free;
  FCorridors.Free;
  FLinks.Free;
  inherited Destroy;
end;

function TWwCsvWriter.LevelFileName(ANumber: Integer; const ASuffix: string): string;
begin
  Result := Format('level_%.2d%s.csv', [ANumber, ASuffix]);
end;

procedure TWwCsvWriter.WriteMatrix(AGrid: TWwGrid; const AFileName: string; AOwners: Boolean);
var
  sl: TStringList;
  x, y: Integer;
  row: string;
begin
  sl := TStringList.Create;
  try
    for y := 0 to AGrid.H - 1 do
    begin
      row := '';
      for x := 0 to AGrid.W - 1 do
      begin
        if x > 0 then row := row + ',';
        if AOwners then
          row := row + IntToStr(AGrid.OwnerAt(x, y))
        else
          row := row + IntToStr(AGrid.CodeAt(x, y));
      end;
      sl.Add(row);
    end;
    sl.SaveToFile(FDir + AFileName);
  finally
    sl.Free;
  end;
end;

procedure TWwCsvWriter.AddLevel(ALevel: TWwLevel);
var
  i, nRooms, nCor, nFork: Integer;
  s: TWwStructure;
  r: TWwRoom;
  c: TWwCorridor;
  l: TWwLink;
begin
  WriteMatrix(ALevel.Grid, LevelFileName(ALevel.Number, ''), False);
  WriteMatrix(ALevel.Grid, LevelFileName(ALevel.Number, '_owner'), True);

  nRooms := 0;
  nCor := 0;
  nFork := 0;
  for i := 0 to ALevel.StructureCount - 1 do
  begin
    s := ALevel.Structures[i];
    if s is TWwRoom then
    begin
      r := TWwRoom(s);
      Inc(nRooms);
      FRooms.Add(Format('%d,%d,%s,%s,%d,%d,%d,%d,%d,%d',
        [ALevel.Number, r.Id, r.KindName, r.Shape.ShapeName, r.X0, r.Y0,
         r.Shape.W, r.Shape.H, r.SizeMetric, r.Cells.Count]));
    end
    else if s is TWwCorridor then
    begin
      c := TWwCorridor(s);
      Inc(nCor);
      FCorridors.Add(Format('%d,%d,%d,%s,%d,%d,%d,%d',
        [ALevel.Number, c.Id, c.Rank, c.RankName, c.FromId, c.ToId,
         c.Path.Count, c.Cells.Count]));
    end
    else if s is TWwFork then
      Inc(nFork);
  end;

  for i := 0 to ALevel.LinkCount - 1 do
  begin
    l := ALevel.LinkAt(i);
    FLinks.Add(Format('%d,%d,%d,%s', [ALevel.Number, l.A, l.B, l.KindName]));
  end;

  FIndex.Add(Format('%d,%s,%s,%d,%d,%s,%d,%d,%d,%d,%d,%d,%d,%d',
    [ALevel.Number, LevelFileName(ALevel.Number, ''), LevelFileName(ALevel.Number, '_owner'),
     ALevel.Grid.W, ALevel.Grid.H, IntToStr(ALevel.Seed), nRooms, nCor, nFork,
     ALevel.LinkCount, ALevel.StairUpX, ALevel.StairUpY,
     ALevel.StairDownX, ALevel.StairDownY]));
end;

procedure TWwCsvWriter.Flush;
begin
  FIndex.SaveToFile(FDir + 'index.csv');
  FRooms.SaveToFile(FDir + 'rooms.csv');
  FCorridors.SaveToFile(FDir + 'corridors.csv');
  FLinks.SaveToFile(FDir + 'links.csv');
end;

{ TWwCsvReader }

constructor TWwCsvReader.Create(const ADir: string);
begin
  inherited Create;
  FDir := IncludeTrailingPathDelimiter(ADir);
  FIndex := TStringList.Create;
  if FileExists(FDir + 'index.csv') then FIndex.LoadFromFile(FDir + 'index.csv');
end;

destructor TWwCsvReader.Destroy;
begin
  FIndex.Free;
  inherited Destroy;
end;

function TWwCsvReader.Field(const ALine: string; AIndex: Integer): string;
var
  i, n, start: Integer;
begin
  Result := '';
  n := 0;
  start := 1;
  for i := 1 to Length(ALine) do
    if ALine[i] = ',' then
    begin
      if n = AIndex then
      begin
        Result := Copy(ALine, start, i - start);
        Exit;
      end;
      Inc(n);
      start := i + 1;
    end;
  if n = AIndex then Result := Copy(ALine, start, Length(ALine) - start + 1);
end;

function TWwCsvReader.LevelCount: Integer;
begin
  Result := FIndex.Count - 1;
  if Result < 0 then Result := 0;
end;

function TWwCsvReader.LoadGrid(ANumber: Integer): TWwGrid;
var
  sl: TStringList;
  fn, line: string;
  x, y, w, h: Integer;
begin
  Result := nil;
  fn := FDir + Format('level_%.2d.csv', [ANumber]);
  if not FileExists(fn) then Exit;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(fn);
    h := sl.Count;
    if h = 0 then Exit;
    w := 1;
    for x := 1 to Length(sl[0]) do
      if sl[0][x] = ',' then Inc(w);
    Result := TWwGrid.Create(w, h);
    for y := 0 to h - 1 do
    begin
      line := sl[y];
      for x := 0 to w - 1 do
        Result.Put(x, y, StrToIntDef(Field(line, x), 0), WW_NO_OWNER);
    end;
  finally
    sl.Free;
  end;
end;

function TWwCsvReader.StairUpX(ANumber: Integer): Integer;
begin
  Result := StrToIntDef(Field(FIndex[ANumber], 10), 1);
end;

function TWwCsvReader.StairUpY(ANumber: Integer): Integer;
begin
  Result := StrToIntDef(Field(FIndex[ANumber], 11), 1);
end;

function TWwCsvReader.StairDownX(ANumber: Integer): Integer;
begin
  Result := StrToIntDef(Field(FIndex[ANumber], 12), 1);
end;

function TWwCsvReader.StairDownY(ANumber: Integer): Integer;
begin
  Result := StrToIntDef(Field(FIndex[ANumber], 13), 1);
end;

end.
