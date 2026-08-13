unit wwGenerator;
{ Генератор уровня.

  Две ошибки исключаются на уровне алгоритма, а не проверкой постфактум:

  1) Наложения. Любая клетка занимается только через TWwGrid.CanOccupy,
     который требует, чтобы сама клетка и все 8 её соседей были свободны
     либо принадлежали явно разрешённому набору структур. Поэтому между
     чужими элементами всегда остаётся минимум клетка монолита, а всякое
     касание — только запланированное (портал комнаты, развилка, отмеченное
     пересечение).

  2) Несвязность. Граф строится остовно: новая комната фиксируется только
     после того, как к ней успешно проложен коридор от уже связанной
     структуры; не проложился — комната стирается и место выбирается заново.
     Дополнительные рёбра (циклы, развилки) только добавляют связей.
     В конце R делает заливку от лестницы и сверяет охват со всеми
     проходимыми клетками — инвариант проверяется, а не предполагается. }

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils, Math, Contnrs, wwCore, wwShapes, wwGrid, wwStruct, wwRules, wwRouter, wwRGeom;

type
  TWwGenerator = class
  private
    FRules: TWwLevelRules;
    FGeom: TWwGeometryClient;
    FRng: TWwRandom;
    FLevel: TWwLevel;
    FGrid: TWwGrid;
    FRouter: TWwRouter;
    FNextId: Integer;
    FRooms: TFPObjectList;      { ссылки на размещённые комнаты, не владеет }
    FCorridors: TFPObjectList;  { ссылки на коридоры, не владеет }
    FSmallLeft, FMediumLeft, FLargeLeft: Integer;
    FReport: string;
    function NewId: Integer;
    function CanvasSide: Integer;
    function MakeSpec(AKind: TWwRoomKind; AAllowComposite: Boolean): TWwShapeSpec;
    function MakeSimpleSpec(AMinSide, AMaxSide: Integer): TWwShapeSpec;
    procedure RollShapeSpec(AMinSide, AMaxSide: Integer; out AType: string;
      out AW, AH: Integer);
    procedure LoadBrushes;
    function PlaceRoomAt(AKind: TWwRoomKind; ASpec: TWwShapeSpec; AShape: TWwShape;
      AX0, AY0: Integer): TWwRoom;
    function PickStartCell(AFrom: TWwStructure; ATargetX, ATargetY, ABrush: Integer;
      AAllowed: TWwIntList; out ASX, ASY: Integer): Boolean;
    function Connect(AFrom, ATo: TWwStructure; ARank, AMaxSteps: Integer;
      ACrossable: TWwStructure): TWwCorridor;
    procedure LinkStructures(ACorridor: TWwCorridor; AOther: TWwStructure);
    function AddRoom(AKind: TWwRoomKind; AAnchor: TWwStructure; AAnchorX, AAnchorY,
      AAnchorSize, ARank: Integer): TWwRoom;
    function AddFork(AAnchor: TWwRoom; ARank: Integer): TWwFork;
    function RandomRoomOfKind(AKind: TWwRoomKind): TWwRoom;
    function RandomCorridorMinRank(AMinRank: Integer): TWwCorridor;
    function RoomCountOfKind(AKind: TWwRoomKind): Integer;
    procedure BuildLarge;
    procedure BuildMedium;
    procedure BuildSmall;
    procedure BuildForks;
    procedure BuildCycles;
    procedure PlaceStairs;
    function TryBuild(ALevelNo: Integer; ASeed: QWord; AAttempt: Integer): TWwLevel;
  public
    constructor Create(const AGeometryScript: string; const AEngine: string = '');
    destructor Destroy; override;
    function Generate(ALevelNo: Integer; ASeed: QWord): TWwLevel;
    property Report: string read FReport;
    property Geometry: TWwGeometryClient read FGeom;
  end;

implementation

constructor TWwGenerator.Create(const AGeometryScript: string; const AEngine: string = '');
begin
  inherited Create;
  FGeom := TWwGeometryClient.Create(AGeometryScript, AEngine);
  FRules := nil;
  FRng := nil;
  FRouter := nil;
  FRooms := TFPObjectList.Create(False);
  FCorridors := TFPObjectList.Create(False);
end;

destructor TWwGenerator.Destroy;
begin
  FRooms.Free;
  FCorridors.Free;
  if FRules <> nil then FRules.Free;
  if FRng <> nil then FRng.Free;
  if FRouter <> nil then FRouter.Free;
  FGeom.Free;
  inherited Destroy;
end;

function TWwGenerator.NewId: Integer;
begin
  Result := FNextId;
  Inc(FNextId);
end;

function TWwGenerator.CanvasSide: Integer;
var
  area: Integer;
begin
  area := FRules.CountFor(wrkSmall) * Sqr(FRules.MaxSideFor(wrkSmall)) +
          FRules.CountFor(wrkMedium) * Sqr(FRules.MaxSideFor(wrkMedium)) +
          FRules.CountFor(wrkLarge) * Sqr(FRules.MaxSideFor(wrkLarge));
  Result := Round(Sqrt(area) * 3.4) + 44;
end;

{ Розыгрыш типа и размеров остаётся на Pascal — вся случайность живёт в
  одном ГПСЧ, иначе воспроизводимость по seed рассыпется. Саму форму строит R. }
procedure TWwGenerator.RollShapeSpec(AMinSide, AMaxSide: Integer; out AType: string;
  out AW, AH: Integer);
var
  roll: Integer;
begin
  AW := FRng.NextInt(AMinSide, AMaxSide);
  AH := FRng.NextInt(AMinSide, AMaxSide);
  roll := FRng.NextInt(1, 100);
  if roll <= 35 then
    AType := 'rect'
  else if roll <= 55 then
    AType := 'square'
  else if roll <= 80 then
    AType := 'ellipse'
  else
    AType := 'circle';
  if (AType = 'square') or (AType = 'circle') then AH := AW;
end;

function TWwGenerator.MakeSimpleSpec(AMinSide, AMaxSide: Integer): TWwShapeSpec;
var
  t: string;
  w, h: Integer;
begin
  RollShapeSpec(AMinSide, AMaxSide, t, w, h);
  Result := TWwShapeSpec.Create;
  Result.AddPart(t, w, h, 0, 0);
end;

procedure TWwGenerator.LoadBrushes;
var
  off: TWwPointList;
  r: Integer;
begin
  off := TWwPointList.Create;
  try
    for r := 1 to 3 do
    begin
      FGeom.BrushOffsets(r, off);
      FRouter.SetBrush(r, off);
    end;
  finally
    off.Free;
  end;
end;

{ Составная комната: несколько намеренно наложенных частей считаются одной
  комнатой. Её размер = сумма длинных сторон/больших диаметров частей и
  не должен превышать максимум для своего типа. }
function TWwGenerator.MakeSpec(AKind: TWwRoomKind; AAllowComposite: Boolean): TWwShapeSpec;
var
  parts, i, budget, per, minSide, ox, oy, dir, pw, ph, prevW, prevH, prevOx, prevOy: Integer;
  ptype: string;
begin
  minSide := FRules.MinSideFor(AKind);
  if (not AAllowComposite) or (not FRules.AllowComposite) or (not FRng.Chance(40)) then
  begin
    Result := MakeSimpleSpec(minSide, FRules.MaxSideFor(AKind));
    Exit;
  end;

  budget := FRules.MaxSideFor(AKind);
  parts := 2;
  if (budget >= 3 * (minSide - 1)) and FRng.Chance(40) then parts := 3;
  per := budget div parts;
  if per < 3 then
  begin
    Result := MakeSimpleSpec(minSide, budget);
    Exit;
  end;

  Result := TWwShapeSpec.Create;
  prevW := 0;
  prevH := 0;
  prevOx := 0;
  prevOy := 0;
  for i := 0 to parts - 1 do
  begin
    RollShapeSpec(3, per, ptype, pw, ph);
    if i = 0 then
    begin
      ox := 0;
      oy := 0;
    end
    else
    begin
      dir := FRng.NextInt(0, 3);
      case dir of
        0: begin ox := prevOx + prevW - FRng.NextInt(1, 2); oy := prevOy + FRng.NextInt(-1, 1); end;
        1: begin ox := prevOx - pw + FRng.NextInt(1, 2); oy := prevOy + FRng.NextInt(-1, 1); end;
        2: begin ox := prevOx + FRng.NextInt(-1, 1); oy := prevOy + prevH - FRng.NextInt(1, 2); end;
      else
        begin ox := prevOx + FRng.NextInt(-1, 1); oy := prevOy - ph + FRng.NextInt(1, 2); end;
      end;
    end;
    { смещения могут быть отрицательными — bbox нормализует R }
    Result.AddPart(ptype, pw, ph, ox, oy);
    prevW := pw;
    prevH := ph;
    prevOx := ox;
    prevOy := oy;
  end;
end;

function TWwGenerator.PlaceRoomAt(AKind: TWwRoomKind; ASpec: TWwShapeSpec; AShape: TWwShape;
  AX0, AY0: Integer): TWwRoom;
var
  x, y, id: Integer;
  room: TWwRoom;
begin
  Result := nil;
  if (AX0 < 2) or (AY0 < 2) or (AX0 + AShape.W > FGrid.W - 2) or (AY0 + AShape.H > FGrid.H - 2) then
    Exit;
  { сначала полная проверка, только потом штамповка }
  for y := 0 to AShape.H - 1 do
    for x := 0 to AShape.W - 1 do
      if AShape.Contains(x, y) then
        if not FGrid.CanOccupy(AX0 + x, AY0 + y, nil) then Exit;

  id := NewId;
  room := TWwRoom.Create(id, AKind, ASpec, AShape, AX0, AY0);
  for y := 0 to AShape.H - 1 do
    for x := 0 to AShape.W - 1 do
      if AShape.Contains(x, y) then
      begin
        FGrid.Put(AX0 + x, AY0 + y, WW_ROOM, id);
        room.Cells.Add(AX0 + x, AY0 + y);
      end;
  if room.Cells.Count = 0 then
  begin
    FGrid.EraseOwner(id);
    room.Free;
    Exit;
  end;
  Result := room;
end;

function TWwGenerator.PickStartCell(AFrom: TWwStructure; ATargetX, ATargetY, ABrush: Integer;
  AAllowed: TWwIntList; out ASX, ASY: Integer): Boolean;
var
  i, d, best, x, y: Integer;
begin
  best := MaxInt;
  ASX := -1;
  ASY := -1;
  for i := 0 to AFrom.Cells.Count - 1 do
  begin
    x := AFrom.Cells.X[i];
    y := AFrom.Cells.Y[i];
    d := Sqr(x - ATargetX) + Sqr(y - ATargetY);
    if (d < best) and FGrid.CanOccupy(x, y, AAllowed) then
    begin
      best := d;
      ASX := x;
      ASY := y;
    end;
  end;
  Result := ASX >= 0;
end;

{ Связь коридора с его концом. Список связей — это записанный замысел
  постройки, а не обход карты: тогда проверка «всякое касание на карте
  зарегистрировано» на стороне R остаётся независимой, а не сверяет карту
  сама с собой. }
procedure TWwGenerator.LinkStructures(ACorridor: TWwCorridor; AOther: TWwStructure);
begin
  if AOther = nil then Exit;
  if AOther is TWwRoom then
    FLevel.AddLink(ACorridor.Id, AOther.Id, wlkPortal)
  else if AOther is TWwFork then
    FLevel.AddLink(ACorridor.Id, AOther.Id, wlkFork)
  else
    FLevel.AddLink(ACorridor.Id, AOther.Id, wlkJunction);
end;

function TWwGenerator.Connect(AFrom, ATo: TWwStructure; ARank, AMaxSteps: Integer;
  ACrossable: TWwStructure): TWwCorridor;
var
  allowed: TWwIntList;
  sx, sy, i, j, cx, cy, o: Integer;
  cor: TWwCorridor;
  brush: TWwPointList;
begin
  Result := nil;
  allowed := TWwIntList.Create;
  brush := TWwPointList.Create;
  try
    allowed.Add(AFrom.Id);
    allowed.Add(ATo.Id);
    if ACrossable <> nil then allowed.Add(ACrossable.Id);

    if not PickStartCell(AFrom, ATo.CenterX, ATo.CenterY, ARank, allowed, sx, sy) then Exit;
    if not FRouter.Route(sx, sy, ATo.Id, ATo.CenterX, ATo.CenterY, ARank, AMaxSteps, allowed) then Exit;

    cor := TWwCorridor.Create(NewId, ARank, AFrom.Id, ATo.Id);
    for i := 0 to FRouter.Path.Count - 1 do
      cor.Path.Add(FRouter.Path.X[i], FRouter.Path.Y[i]);
    { осевая линия разворачивается в вектор клеток на R }
    FGeom.ExpandPath(ARank, cor.Path, brush);
    for j := 0 to brush.Count - 1 do
    begin
      cx := brush.X[j];
      cy := brush.Y[j];
      if not FGrid.InBounds(cx, cy) then Continue;
      o := FGrid.OwnerAt(cx, cy);
      if o = WW_NO_OWNER then
      begin
        FGrid.Put(cx, cy, cor.CodeForRank, cor.Id);
        cor.Cells.Add(cx, cy);
      end
      else if (ACrossable <> nil) and (o = ACrossable.Id) then
      begin
        { запланированное пересечение: клетка остаётся за прежним владельцем,
          но помечается как перекрёсток }
        FGrid.PutCode(cx, cy, WW_JUNCTION);
        FLevel.AddLink(cor.Id, o, wlkJunction);
      end;
    end;
    FLevel.AddStructure(cor);
    FCorridors.Add(cor);
    LinkStructures(cor, AFrom);
    LinkStructures(cor, ATo);
    Result := cor;
  finally
    allowed.Free;
    brush.Free;
  end;
end;

function TWwGenerator.AddRoom(AKind: TWwRoomKind; AAnchor: TWwStructure; AAnchorX, AAnchorY,
  AAnchorSize, ARank: Integer): TWwRoom;
var
  attempt, gap, maxLen, dist, x0, y0, cx, cy: Integer;
  ang: Double;
  spec: TWwShapeSpec;
  shape: TWwShape;
  room: TWwRoom;
  cor: TWwCorridor;
begin
  Result := nil;
  for attempt := 1 to 90 do
  begin
    spec := MakeSpec(AKind, True);
    shape := FGeom.Build(spec);
    maxLen := FRules.MaxCorridorLength(shape.SizeMetric, AAnchorSize);
    gap := FRng.NextInt(3, maxLen - 4);
    dist := (AAnchorSize + shape.SizeMetric) div 2 + gap;
    ang := FRng.NextFloat * 2 * Pi;
    cx := AAnchorX + Round(Cos(ang) * dist);
    cy := AAnchorY + Round(Sin(ang) * dist);
    x0 := cx - shape.W div 2;
    y0 := cy - shape.H div 2;

    room := PlaceRoomAt(AKind, spec, shape, x0, y0);
    if room = nil then
    begin
      shape.Free;
      spec.Free;
      Continue;
    end;

    if AAnchor = nil then
    begin
      FLevel.AddStructure(room);
      FRooms.Add(room);
      Result := room;
      Exit;
    end;

    cor := Connect(AAnchor, room, ARank, maxLen, nil);
    if cor = nil then
    begin
      FGrid.EraseOwner(room.Id);
      room.Free;
      Continue;
    end;

    FLevel.AddStructure(room);
    FRooms.Add(room);
    if AAnchor is TWwRoom then
    begin
      TWwRoom(AAnchor).Connections.AddUnique(room.Id);
      room.Connections.AddUnique(AAnchor.Id);
    end;
    Result := room;
    Exit;
  end;
end;

{ Развилка: коридор ранга r упирается одним концом не в комнату, а в узел,
  от которого расходятся коридоры ранга r-1. }
function TWwGenerator.AddFork(AAnchor: TWwRoom; ARank: Integer): TWwFork;
var
  attempt, dist, cx, cy, x, y, maxLen, side: Integer;
  ang: Double;
  fork: TWwFork;
  cor: TWwCorridor;
  ok: Boolean;
begin
  Result := nil;
  side := ARank;
  for attempt := 1 to 80 do
  begin
    maxLen := FRules.MaxCorridorLength(AAnchor.SizeMetric, side);
    dist := AAnchor.SizeMetric div 2 + FRng.NextInt(4, maxLen - 4);
    ang := FRng.NextFloat * 2 * Pi;
    cx := AAnchor.CenterX + Round(Cos(ang) * dist);
    cy := AAnchor.CenterY + Round(Sin(ang) * dist);

    ok := True;
    for y := 0 to side - 1 do
      for x := 0 to side - 1 do
        if not FGrid.CanOccupy(cx + x, cy + y, nil) then ok := False;
    if not ok then Continue;

    fork := TWwFork.Create(NewId, ARank);
    for y := 0 to side - 1 do
      for x := 0 to side - 1 do
      begin
        FGrid.Put(cx + x, cy + y, WW_FORK, fork.Id);
        fork.Cells.Add(cx + x, cy + y);
      end;
    FLevel.AddStructure(fork);

    cor := Connect(AAnchor, fork, ARank, maxLen, nil);
    if cor = nil then
    begin
      FGrid.EraseOwner(fork.Id);
      FLevel.RemoveStructure(fork);
      Continue;
    end;
    Result := fork;
    Exit;
  end;
end;

function TWwGenerator.RandomRoomOfKind(AKind: TWwRoomKind): TWwRoom;
var
  pool: TFPObjectList;
  i: Integer;
begin
  Result := nil;
  pool := TFPObjectList.Create(False);
  try
    for i := 0 to FRooms.Count - 1 do
      if TWwRoom(FRooms[i]).Kind = AKind then pool.Add(FRooms[i]);
    if pool.Count = 0 then Exit;
    Result := TWwRoom(pool[FRng.NextInt(0, pool.Count - 1)]);
  finally
    pool.Free;
  end;
end;

function TWwGenerator.RandomCorridorMinRank(AMinRank: Integer): TWwCorridor;
var
  pool: TFPObjectList;
  i: Integer;
begin
  Result := nil;
  pool := TFPObjectList.Create(False);
  try
    for i := 0 to FCorridors.Count - 1 do
      if TWwCorridor(FCorridors[i]).Rank >= AMinRank then pool.Add(FCorridors[i]);
    if pool.Count = 0 then Exit;
    Result := TWwCorridor(pool[FRng.NextInt(0, pool.Count - 1)]);
  finally
    pool.Free;
  end;
end;

function TWwGenerator.RoomCountOfKind(AKind: TWwRoomKind): Integer;
var
  i, n: Integer;
begin
  n := 0;
  for i := 0 to FRooms.Count - 1 do
    if TWwRoom(FRooms[i]).Kind = AKind then Inc(n);
  Result := n;
end;

procedure TWwGenerator.BuildLarge;
var
  i: Integer;
  anchor, room: TWwRoom;
begin
  for i := 1 to FLargeLeft do
  begin
    if FRooms.Count = 0 then
      room := AddRoom(wrkLarge, nil, FGrid.W div 2, FGrid.H div 2, 0, 0)
    else
    begin
      anchor := RandomRoomOfKind(wrkLarge);
      if anchor = nil then anchor := TWwRoom(FRooms[0]);
      room := AddRoom(wrkLarge, anchor, anchor.CenterX, anchor.CenterY, anchor.SizeMetric,
        FRules.CorridorRank(wrkLarge, anchor.Kind));
    end;
    if room <> nil then Dec(FLargeLeft);
  end;
end;

procedure TWwGenerator.BuildMedium;
var
  i: Integer;
  anchor, room: TWwRoom;
begin
  i := 0;
  while (FMediumLeft > 0) and (i < 200) do
  begin
    Inc(i);
    if FRooms.Count = 0 then
      room := AddRoom(wrkMedium, nil, FGrid.W div 2, FGrid.H div 2, 0, 0)
    else
    begin
      anchor := RandomRoomOfKind(wrkLarge);
      if (anchor = nil) or FRng.Chance(40) then
      begin
        anchor := RandomRoomOfKind(wrkMedium);
        if anchor = nil then anchor := RandomRoomOfKind(wrkLarge);
      end;
      if anchor = nil then anchor := TWwRoom(FRooms[0]);
      room := AddRoom(wrkMedium, anchor, anchor.CenterX, anchor.CenterY, anchor.SizeMetric,
        FRules.CorridorRank(wrkMedium, anchor.Kind));
    end;
    if room <> nil then Dec(FMediumLeft);
  end;
end;

procedure TWwGenerator.BuildSmall;
var
  i, sx, sy, rank: Integer;
  anchorRoom, room: TWwRoom;
  anchorCor: TWwCorridor;
begin
  i := 0;
  while (FSmallLeft > 0) and (i < 300) do
  begin
    Inc(i);
    room := nil;
    if FRooms.Count = 0 then
      room := AddRoom(wrkSmall, nil, FGrid.W div 2, FGrid.H div 2, 0, 0)
    else
    begin
      anchorCor := nil;
      if FRng.Chance(55) then anchorCor := RandomCorridorMinRank(2);
      if anchorCor <> nil then
      begin
        { побочный коридор ответвляется от более широкого — берём клетку
          в середине родительского коридора }
        sx := anchorCor.Path.X[anchorCor.Path.Count div 2];
        sy := anchorCor.Path.Y[anchorCor.Path.Count div 2];
        room := AddRoom(wrkSmall, anchorCor, sx, sy, anchorCor.Rank, 1);
      end;
      if room = nil then
      begin
        anchorRoom := RandomRoomOfKind(wrkSmall);
        if (anchorRoom = nil) or FRng.Chance(25) then
        begin
          anchorRoom := RandomRoomOfKind(wrkMedium);
          if anchorRoom = nil then anchorRoom := RandomRoomOfKind(wrkLarge);
          if anchorRoom = nil then anchorRoom := RandomRoomOfKind(wrkSmall);
        end;
        if anchorRoom <> nil then
        begin
          rank := FRules.CorridorRank(wrkSmall, anchorRoom.Kind);
          room := AddRoom(wrkSmall, anchorRoom, anchorRoom.CenterX, anchorRoom.CenterY,
            anchorRoom.SizeMetric, rank);
        end;
      end;
    end;
    if room <> nil then Dec(FSmallLeft);
  end;
end;

procedure TWwGenerator.BuildForks;
var
  anchor: TWwRoom;
  fork: TWwFork;
  room: TWwRoom;
  n, maxLen: Integer;
begin
  { развилка главного коридора: большая комната -> узел -> два второстепенных }
  if (FRules.MaxRank >= 3) and (FMediumLeft >= 2) then
  begin
    anchor := RandomRoomOfKind(wrkLarge);
    if anchor <> nil then
    begin
      fork := AddFork(anchor, 3);
      if fork <> nil then
        for n := 1 to 2 do
        begin
          room := AddRoom(wrkMedium, fork, fork.CenterX, fork.CenterY, 3, 2);
          if room <> nil then Dec(FMediumLeft);
        end;
    end;
  end;

  { развилка второстепенного: средняя комната -> узел -> два побочных }
  if (FRules.MaxRank >= 2) and (FSmallLeft >= 2) then
  begin
    anchor := RandomRoomOfKind(wrkMedium);
    if anchor <> nil then
    begin
      fork := AddFork(anchor, 2);
      if fork <> nil then
        for n := 1 to 2 do
        begin
          room := AddRoom(wrkSmall, fork, fork.CenterX, fork.CenterY, 2, 1);
          if room <> nil then Dec(FSmallLeft);
        end;
    end;
  end;
  maxLen := 0;
  if maxLen > 0 then Exit;
end;

{ Дополнительные рёбра: замыкают петли и дают запланированные пересечения. }
procedure TWwGenerator.BuildCycles;
var
  tries, i, j, rank, maxLen, d: Integer;
  a, b: TWwRoom;
  cross: TWwCorridor;
begin
  if FRules.Level < 4 then Exit;
  for tries := 1 to 3 + FRules.Level div 3 do
  begin
    if FRooms.Count < 3 then Exit;
    i := FRng.NextInt(0, FRooms.Count - 1);
    j := FRng.NextInt(0, FRooms.Count - 1);
    if i = j then Continue;
    a := TWwRoom(FRooms[i]);
    b := TWwRoom(FRooms[j]);
    if a.Connections.Contains(b.Id) then Continue;
    d := Round(Sqrt(Sqr(a.CenterX - b.CenterX) + Sqr(a.CenterY - b.CenterY)));
    maxLen := FRules.MaxCorridorLength(a.SizeMetric, b.SizeMetric);
    if d > maxLen + (a.SizeMetric + b.SizeMetric) div 2 then Continue;
    rank := FRules.CorridorRank(a.Kind, b.Kind);
    cross := nil;
    if FRng.Chance(50) then cross := RandomCorridorMinRank(rank);
    if Connect(a, b, rank, maxLen, cross) <> nil then
    begin
      a.Connections.AddUnique(b.Id);
      b.Connections.AddUnique(a.Id);
    end;
  end;
end;

procedure TWwGenerator.PlaceStairs;
var
  i, best, d, ux, uy, dx2, dy2: Integer;
  first, far: TWwRoom;
begin
  if FRooms.Count = 0 then Exit;
  first := TWwRoom(FRooms[0]);
  ux := first.CenterX;
  uy := first.CenterY;
  if not FGrid.IsWalkable(ux, uy) then
  begin
    ux := first.Cells.X[0];
    uy := first.Cells.Y[0];
  end;
  far := first;
  best := -1;
  for i := 0 to FRooms.Count - 1 do
  begin
    d := Sqr(TWwRoom(FRooms[i]).CenterX - ux) + Sqr(TWwRoom(FRooms[i]).CenterY - uy);
    if d > best then
    begin
      best := d;
      far := TWwRoom(FRooms[i]);
    end;
  end;
  dx2 := far.CenterX;
  dy2 := far.CenterY;
  if not FGrid.IsWalkable(dx2, dy2) then
  begin
    dx2 := far.Cells.X[far.Cells.Count div 2];
    dy2 := far.Cells.Y[far.Cells.Count div 2];
  end;
  FGrid.PutCode(ux, uy, WW_STAIR_UP);
  FGrid.PutCode(dx2, dy2, WW_STAIR_DOWN);
  FLevel.SetStairs(ux, uy, dx2, dy2);
end;

function TWwGenerator.TryBuild(ALevelNo: Integer; ASeed: QWord; AAttempt: Integer): TWwLevel;
var
  side: Integer;
  cropped: TWwGrid;
  x, y, offX, offY, reached, total, x0, y0, x1, y1: Integer;
begin
  Result := nil;
  if FRng <> nil then FreeAndNil(FRng);
  if FRouter <> nil then FreeAndNil(FRouter);
  FRooms.Clear;
  FCorridors.Clear;
  FNextId := 1;

  FRng := TWwRandom.Create(ASeed xor (QWord(ALevelNo) * QWord(2654435761)) xor
                           (QWord(AAttempt) * QWord(40503)));
  side := CanvasSide;
  FGrid := TWwGrid.Create(side, side);
  FRouter := TWwRouter.Create(FGrid);
  LoadBrushes;
  FLevel := TWwLevel.Create(ALevelNo, ASeed);
  FLevel.Grid := FGrid;

  FSmallLeft := FRules.CountFor(wrkSmall);
  FMediumLeft := FRules.CountFor(wrkMedium);
  FLargeLeft := FRules.CountFor(wrkLarge);

  BuildLarge;
  BuildMedium;
  BuildForks;
  BuildSmall;
  BuildCycles;
  PlaceStairs;

  { Заливка от лестницы, вывод стен и рамка — одним обращением к R.
    Не сошёлся охват — этаж распался на куски, значит попытка бракуется. }
  if not FGeom.Finalize(FGrid, FLevel.StairUpX, FLevel.StairUpY,
                        reached, total, x0, y0, x1, y1) then
  begin
    FreeAndNil(FLevel);
    FGrid := nil;
    Exit;
  end;

  cropped := FGrid.CopyRegion(x0, y0, x1, y1);
  offX := -x0;
  offY := -y0;
  FLevel.ReplaceGrid(cropped);
  FLevel.ShiftStructures(offX, offY);
  FGrid := cropped;
  { пересчитать координаты лестниц в обрезанной сетке }
  for y := 0 to cropped.H - 1 do
    for x := 0 to cropped.W - 1 do
    begin
      if cropped.CodeAt(x, y) = WW_STAIR_UP then
      begin
        FLevel.StairUpX := x;
        FLevel.StairUpY := y;
      end
      else if cropped.CodeAt(x, y) = WW_STAIR_DOWN then
      begin
        FLevel.StairDownX := x;
        FLevel.StairDownY := y;
      end;
    end;
  Result := FLevel;
end;

function TWwGenerator.Generate(ALevelNo: Integer; ASeed: QWord): TWwLevel;
var
  attempt: Integer;
  lv: TWwLevel;
begin
  if FRules <> nil then FreeAndNil(FRules);
  FRules := TWwLevelRules.Create(ALevelNo);
  Result := nil;
  for attempt := 0 to 11 do
  begin
    lv := TryBuild(ALevelNo, ASeed, attempt);
    if lv <> nil then
    begin
      FReport := Format('level %d: rooms=%d corridors=%d links=%d grid=%dx%d attempt=%d',
        [ALevelNo, FRooms.Count, FCorridors.Count, lv.LinkCount, lv.Grid.W, lv.Grid.H, attempt]);
      Result := lv;
      Exit;
    end;
  end;
  FReport := Format('level %d: FAILED after 12 attempts', [ALevelNo]);
end;

end.
