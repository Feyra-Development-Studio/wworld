unit wwGrid;
{ Сетка уровня. Каждая клетка хранит код и идентификатор владельца —
  структуры (комната/коридор/развилка), которой клетка принадлежит.
  Владелец — это то, что алгоритмически исключает наложения: занять клетку
  можно только если она и все её 8 соседей свободны либо принадлежат
  разрешённому набору структур. }

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils, Classes, wwCore;

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
    function AsDigits: string;
    procedure ApplyDigits(const ADigits: string);
    function IsWalkable(AX, AY: Integer): Boolean;
    function CountWalkable: Integer;
    function CopyRegion(AX0, AY0, AX1, AY1: Integer): TWwGrid;
    function AsText: string;
    function SameAs(AOther: TWwGrid): Boolean;
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

{ Карта уезжает на анализ в R строкой цифр: коды клеток укладываются в 0..9. }
function TWwGrid.AsDigits: string;
var
  i: Integer;
begin
  SetLength(Result, FW * FH);
  for i := 0 to FW * FH - 1 do
    Result[i + 1] := Chr(Ord('0') + FCode[i]);
end;

procedure TWwGrid.ApplyDigits(const ADigits: string);
var
  i: Integer;
begin
  if Length(ADigits) <> FW * FH then
    raise Exception.CreateFmt('карта из R: ожидалось %d клеток, получено %d',
      [FW * FH, Length(ADigits)]);
  for i := 0 to FW * FH - 1 do
    FCode[i] := Ord(ADigits[i + 1]) - Ord('0');
end;

{ Вырезка по рамке, посчитанной на R. }
function TWwGrid.CopyRegion(AX0, AY0, AX1, AY1: Integer): TWwGrid;
var
  x, y, nw, nh: Integer;
  g: TWwGrid;
begin
  if AX0 < 0 then AX0 := 0;
  if AY0 < 0 then AY0 := 0;
  if AX1 > FW - 1 then AX1 := FW - 1;
  if AY1 > FH - 1 then AY1 := FH - 1;
  nw := AX1 - AX0 + 1;
  nh := AY1 - AY0 + 1;
  if (nw < 1) or (nh < 1) then
  begin
    Result := TWwGrid.Create(1, 1);
    Exit;
  end;
  g := TWwGrid.Create(nw, nh);
  for y := 0 to nh - 1 do
    for x := 0 to nw - 1 do
      g.Put(x, y, FCode[Index(AX0 + x, AY0 + y)], FOwner[Index(AX0 + x, AY0 + y)]);
  Result := g;
end;

{ Матрица кодов строками — и для CSV, и для сверки восстановленной карты
  с исходной. }
function TWwGrid.AsText: string;
var
  x, y: Integer;
  sb: TStringList;
  row: string;
begin
  sb := TStringList.Create;
  try
    for y := 0 to FH - 1 do
    begin
      row := '';
      for x := 0 to FW - 1 do
      begin
        if x > 0 then row := row + ',';
        row := row + IntToStr(FCode[Index(x, y)]);
      end;
      sb.Add(row);
    end;
    Result := sb.Text;
  finally
    sb.Free;
  end;
end;

function TWwGrid.SameAs(AOther: TWwGrid): Boolean;
begin
  Result := (AOther <> nil) and (AOther.W = FW) and (AOther.H = FH) and
            (AOther.AsText = AsText);
end;

end.
