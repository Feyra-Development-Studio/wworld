unit wwRebuild;
{ Восстановление растровой карты из графа-инструкции.

  JSON хранит только инструкции: спецификации форм, осевые линии коридоров,
  узлы и лестницы. Клетки строятся заново тем же геометрическим сервером на
  R, что и при генерации, и в том же порядке — по возрастанию идентификатора,
  а он выдаётся строго по ходу построения. Поэтому восстановленная карта
  обязана совпасть с исходной клетка в клетку; это и проверяется прогоном
  --test. }

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils, Contnrs, wwCore, wwShapes, wwGrid, wwStruct, wwRGeom;

type
  TWwRebuilder = class
  private
    FGeom: TWwGeometryClient;
    FCells: TWwPointList;
    procedure StampRoom(ALevel: TWwLevel; ARoom: TWwRoom);
    procedure StampFork(ALevel: TWwLevel; AFork: TWwFork);
    procedure StampCorridor(ALevel: TWwLevel; ACorridor: TWwCorridor);
  public
    constructor Create(AGeom: TWwGeometryClient);
    destructor Destroy; override;
    procedure Rebuild(ALevel: TWwLevel);
  end;

implementation

constructor TWwRebuilder.Create(AGeom: TWwGeometryClient);
begin
  inherited Create;
  FGeom := AGeom;
  FCells := TWwPointList.Create;
end;

destructor TWwRebuilder.Destroy;
begin
  FCells.Free;
  inherited Destroy;
end;

procedure TWwRebuilder.StampRoom(ALevel: TWwLevel; ARoom: TWwRoom);
var
  x, y: Integer;
  shape: TWwShape;
begin
  shape := FGeom.Build(ARoom.Spec);
  ARoom.AssignShape(shape);
  ARoom.Cells.Clear;
  for y := 0 to shape.H - 1 do
    for x := 0 to shape.W - 1 do
      if shape.Contains(x, y) then
      begin
        ALevel.Grid.Put(ARoom.X0 + x, ARoom.Y0 + y, WW_ROOM, ARoom.Id);
        ARoom.Cells.Add(ARoom.X0 + x, ARoom.Y0 + y);
      end;
end;

procedure TWwRebuilder.StampFork(ALevel: TWwLevel; AFork: TWwFork);
var
  i: Integer;
begin
  for i := 0 to AFork.Cells.Count - 1 do
    ALevel.Grid.Put(AFork.Cells.X[i], AFork.Cells.Y[i], WW_FORK, AFork.Id);
end;

procedure TWwRebuilder.StampCorridor(ALevel: TWwLevel; ACorridor: TWwCorridor);
var
  i, cx, cy, o: Integer;
  other: TWwStructure;
begin
  { клетки коридора разворачивает R по сохранённой осевой линии }
  FGeom.ExpandPath(ACorridor.Rank, ACorridor.Path, FCells);
  ACorridor.Cells.Clear;
  for i := 0 to FCells.Count - 1 do
  begin
    cx := FCells.X[i];
    cy := FCells.Y[i];
    if not ALevel.Grid.InBounds(cx, cy) then Continue;
    o := ALevel.Grid.OwnerAt(cx, cy);
    if o = WW_NO_OWNER then
    begin
      ALevel.Grid.Put(cx, cy, ACorridor.CodeForRank, ACorridor.Id);
      ACorridor.Cells.Add(cx, cy);
    end
    else if (o <> ACorridor.FromId) and (o <> ACorridor.ToId) then
    begin
      { Чужая клетка на пути бывает двух видов. Стык с собственным концом —
        это вход в комнату, узел или родительский коридор ответвления, он
        сохраняет свой код. Всё остальное возможно только там, где при
        генерации было запланированное пересечение коридоров. }
      other := ALevel.StructureById(o);
      if (other <> nil) and (other is TWwCorridor) then
        ALevel.Grid.PutCode(cx, cy, WW_JUNCTION);
    end;
  end;
end;

procedure TWwRebuilder.Rebuild(ALevel: TWwLevel);
var
  ordered: TFPObjectList;
  i: Integer;
  s: TWwStructure;
begin
  ordered := ALevel.SortedByIdCopy;
  try
    for i := 0 to ordered.Count - 1 do
    begin
      s := TWwStructure(ordered[i]);
      if s is TWwRoom then
        StampRoom(ALevel, TWwRoom(s))
      else if s is TWwFork then
        StampFork(ALevel, TWwFork(s))
      else if s is TWwCorridor then
        StampCorridor(ALevel, TWwCorridor(s));
    end;
  finally
    ordered.Free;
  end;

  FGeom.ApplyWalls(ALevel.Grid);
  if (ALevel.StairUpX >= 0) then
    ALevel.Grid.PutCode(ALevel.StairUpX, ALevel.StairUpY, WW_STAIR_UP);
  if (ALevel.StairDownX >= 0) then
    ALevel.Grid.PutCode(ALevel.StairDownX, ALevel.StairDownY, WW_STAIR_DOWN);
end;

end.
