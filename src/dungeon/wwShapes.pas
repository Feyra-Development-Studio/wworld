unit wwShapes;
{ Форма комнаты — маска, посчитанная на R.

  Здесь намеренно нет никакой геометрии: ни формулы эллипса, ни объединения
  составных частей. Всё это считает scripts/geometry.R, чтобы правило жило в
  одном месте. Класс хранит готовую маску и отвечает на вопрос «входит ли
  клетка в комнату». }

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils;

type
  TWwShape = class
  private
    FW, FH, FMetric: Integer;
    FName: string;
    FMask: string;
  public
    constructor Create(const AName: string; AW, AH, AMetric: Integer; const AMask: string);
    function Contains(ALX, ALY: Integer): Boolean;
    function CellCount: Integer;
    function ShapeName: string;
    function SizeMetric: Integer;
    property W: Integer read FW;
    property H: Integer read FH;
    property Mask: string read FMask;
  end;

implementation

constructor TWwShape.Create(const AName: string; AW, AH, AMetric: Integer; const AMask: string);
begin
  inherited Create;
  FName := AName;
  FW := AW;
  FH := AH;
  FMetric := AMetric;
  FMask := AMask;
  if Length(FMask) <> FW * FH then
    raise Exception.CreateFmt('маска %s: ожидалось %d клеток, получено %d',
      [AName, FW * FH, Length(FMask)]);
end;

function TWwShape.Contains(ALX, ALY: Integer): Boolean;
begin
  if (ALX < 0) or (ALY < 0) or (ALX >= FW) or (ALY >= FH) then
    Result := False
  else
    Result := FMask[ALY * FW + ALX + 1] = '1';
end;

function TWwShape.CellCount: Integer;
var
  i, n: Integer;
begin
  n := 0;
  for i := 1 to Length(FMask) do
    if FMask[i] = '1' then Inc(n);
  Result := n;
end;

function TWwShape.ShapeName: string;
begin
  Result := FName;
end;

function TWwShape.SizeMetric: Integer;
begin
  Result := FMetric;
end;

end.
