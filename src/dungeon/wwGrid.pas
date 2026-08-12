unit wwGrid;
{ Сетка уровня. Каждая клетка хранит код и идентификатор владельца —
  структуры (комната/коридор/развилка), которой клетка принадлежит.
  Владелец — это то, что алгоритмически исключает наложения: занять клетку
  можно только если она и все её 8 соседей свободны либо принадлежат
  разрешённому набору структур. }

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils, wwCore;

type
  TWwGrid = class
  private
    FW, FH: Integer;
    FCode: array of Byte;
    FOwner: array of Integer;
    function Index(AX, AY: Integer): Integer;
  public
    constructor Create(AW, AH: Integer);
    function InBounds(AX, AY: Integer): Boolean;
    function CodeAt(AX, AY: Integer): Byte;
    function OwnerAt(AX, AY: Integer): Integer;
    procedure Put(AX, AY: Integer; ACode: Byte; AOwner: Integer);
    procedure PutCode(AX, AY: Integer; ACode: Byte);
    function CellAllowed(AX, AY: Integer; AAllowed: TWwIntList): Boolean;
    function CanOccupy(AX, AY: Integer; AAllowed: TWwIntList): Boolean;
    procedure EraseOwner(AOwnerId: Integer);
    procedure DeriveWalls;
    function IsWalkable(AX, AY: Integer): Boolean;
    function CountWalkable: Integer;
    function CroppedCopy(AMargin: Integer): TWwGrid;
    property W: Integer read FW;
    property H: Integer read FH;
  end;

implementation

constructor TWwGrid.Create(AW, AH: Integer);
var
  i: Integer;
begin
  inherited Create;
  FW := AW;
  FH := AH;
  SetLength(FCode, AW * AH);
  SetLength(FOwner, AW * AH);
  for i := 0 to AW * AH - 1 do
  begin
    FCode[i] := WW_ROCK;
    FOwner[i] := WW_NO_OWNER;
  end;
end;

function TWwGrid.Index(AX, AY: Integer): Integer;
begin
  Result := AY * FW + AX;
end;

function TWwGrid.InBounds(AX, AY: Integer): Boolean;
begin
  Result := (AX >= 0) and (AY >= 0) and (AX < FW) and (AY < FH);
end;

function TWwGrid.CodeAt(AX, AY: Integer): Byte;
begin
  if InBounds(AX, AY) then Result := FCode[Index(AX, AY)] else Result := WW_ROCK;
end;

function TWwGrid.OwnerAt(AX, AY: Integer): Integer;
begin
  if InBounds(AX, AY) then Result := FOwner[Index(AX, AY)] else Result := WW_NO_OWNER;
end;

procedure TWwGrid.Put(AX, AY: Integer; ACode: Byte; AOwner: Integer);
begin
  if not InBounds(AX, AY) then Exit;
  FCode[Index(AX, AY)] := ACode;
  FOwner[Index(AX, AY)] := AOwner;
end;

procedure TWwGrid.PutCode(AX, AY: Integer; ACode: Byte);
begin
  if not InBounds(AX, AY) then Exit;
  FCode[Index(AX, AY)] := ACode;
end;

function TWwGrid.CellAllowed(AX, AY: Integer; AAllowed: TWwIntList): Boolean;
var
  o: Integer;
begin
  if not InBounds(AX, AY) then
  begin
    Result := False;
    Exit;
  end;
  o := FOwner[Index(AX, AY)];
  Result := (o = WW_NO_OWNER) or ((AAllowed <> nil) and AAllowed.Contains(o));
end;

{ Клетку можно занять, только если она и весь её 8-окрестный периметр
  свободны либо принадлежат разрешённым структурам. Это гарантирует
  минимум одну клетку монолита между чужими элементами — «слипшихся»
  комнат и незапланированных касаний коридоров быть не может. }
function TWwGrid.CanOccupy(AX, AY: Integer; AAllowed: TWwIntList): Boolean;
var
  dx, dy: Integer;
begin
  for dy := -1 to 1 do
    for dx := -1 to 1 do
      if not CellAllowed(AX + dx, AY + dy, AAllowed) then
      begin
        Result := False;
        Exit;
      end;
  Result := True;
end;

procedure TWwGrid.EraseOwner(AOwnerId: Integer);
var
  i: Integer;
begin
  for i := 0 to FW * FH - 1 do
    if FOwner[i] = AOwnerId then
    begin
      FOwner[i] := WW_NO_OWNER;
      FCode[i] := WW_ROCK;
    end;
end;

function TWwGrid.IsWalkable(AX, AY: Integer): Boolean;
var
  c: Byte;
begin
  c := CodeAt(AX, AY);
  Result := (c >= WW_ROOM) and (c <= WW_STAIR_DOWN);
end;

function TWwGrid.CountWalkable: Integer;
var
  x, y, n: Integer;
begin
  n := 0;
  for y := 0 to FH - 1 do
    for x := 0 to FW - 1 do
      if IsWalkable(x, y) then Inc(n);
  Result := n;
end;

procedure TWwGrid.DeriveWalls;
var
  x, y, dx, dy: Integer;
  touch: Boolean;
begin
  for y := 0 to FH - 1 do
    for x := 0 to FW - 1 do
      if FCode[Index(x, y)] = WW_ROCK then
      begin
        touch := False;
        for dy := -1 to 1 do
          for dx := -1 to 1 do
            if IsWalkable(x + dx, y + dy) then touch := True;
        if touch then FCode[Index(x, y)] := WW_WALL;
      end;
end;

function TWwGrid.CroppedCopy(AMargin: Integer): TWwGrid;
var
  x, y, minX, minY, maxX, maxY, nw, nh: Integer;
  g: TWwGrid;
  found: Boolean;
begin
  minX := FW; minY := FH; maxX := -1; maxY := -1;
  found := False;
  for y := 0 to FH - 1 do
    for x := 0 to FW - 1 do
      if FCode[Index(x, y)] <> WW_ROCK then
      begin
        found := True;
        if x < minX then minX := x;
        if y < minY then minY := y;
        if x > maxX then maxX := x;
        if y > maxY then maxY := y;
      end;
  if not found then
  begin
    Result := TWwGrid.Create(1, 1);
    Exit;
  end;
  minX := minX - AMargin; if minX < 0 then minX := 0;
  minY := minY - AMargin; if minY < 0 then minY := 0;
  maxX := maxX + AMargin; if maxX > FW - 1 then maxX := FW - 1;
  maxY := maxY + AMargin; if maxY > FH - 1 then maxY := FH - 1;
  nw := maxX - minX + 1;
  nh := maxY - minY + 1;
  g := TWwGrid.Create(nw, nh);
  for y := 0 to nh - 1 do
    for x := 0 to nw - 1 do
      g.Put(x, y, FCode[Index(minX + x, minY + y)], FOwner[Index(minX + x, minY + y)]);
  Result := g;
end;

end.
