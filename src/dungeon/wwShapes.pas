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
  { Инструкция построения формы: тип и размеры частей. Именно она попадает
    в JSON — растр из неё восстанавливается запросом к геометрии на R, а не
    хранится. }
  TWwShapeSpec = class
  private
    FTypes: array of string;
    FWs, FHs, FOXs, FOYs: array of Integer;
  public
    procedure AddPart(const AType: string; AW, AH, AOX, AOY: Integer);
    function PartCount: Integer;
    function PartType(AIndex: Integer): string;
    function PartW(AIndex: Integer): Integer;
    function PartH(AIndex: Integer): Integer;
    function PartOX(AIndex: Integer): Integer;
    function PartOY(AIndex: Integer): Integer;
    function IsComposite: Boolean;
    function ShapeName: string;
    function Request: string;
  end;

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

{ TWwShapeSpec }

procedure TWwShapeSpec.AddPart(const AType: string; AW, AH, AOX, AOY: Integer);
var
  n: Integer;
begin
  n := Length(FTypes);
  SetLength(FTypes, n + 1);
  SetLength(FWs, n + 1);
  SetLength(FHs, n + 1);
  SetLength(FOXs, n + 1);
  SetLength(FOYs, n + 1);
  FTypes[n] := AType;
  FWs[n] := AW;
  FHs[n] := AH;
  FOXs[n] := AOX;
  FOYs[n] := AOY;
end;

function TWwShapeSpec.PartCount: Integer;
begin
  Result := Length(FTypes);
end;

function TWwShapeSpec.PartType(AIndex: Integer): string;
begin
  Result := FTypes[AIndex];
end;

function TWwShapeSpec.PartW(AIndex: Integer): Integer;
begin
  Result := FWs[AIndex];
end;

function TWwShapeSpec.PartH(AIndex: Integer): Integer;
begin
  Result := FHs[AIndex];
end;

function TWwShapeSpec.PartOX(AIndex: Integer): Integer;
begin
  Result := FOXs[AIndex];
end;

function TWwShapeSpec.PartOY(AIndex: Integer): Integer;
begin
  Result := FOYs[AIndex];
end;

function TWwShapeSpec.IsComposite: Boolean;
begin
  Result := Length(FTypes) > 1;
end;

function TWwShapeSpec.ShapeName: string;
begin
  if IsComposite then Result := 'composite' else Result := FTypes[0];
end;

{ Строка запроса к геометрическому серверу. Одна и та же и при генерации,
  и при восстановлении из JSON — поэтому маска гарантированно совпадает. }
function TWwShapeSpec.Request: string;
var
  i: Integer;
begin
  if not IsComposite then
  begin
    if (FTypes[0] = 'square') or (FTypes[0] = 'circle') then
      Result := Format('SHAPE %s %d', [FTypes[0], FWs[0]])
    else
      Result := Format('SHAPE %s %d %d', [FTypes[0], FWs[0], FHs[0]]);
    Exit;
  end;
  Result := Format('COMPOSITE %d', [PartCount]);
  for i := 0 to PartCount - 1 do
    Result := Result + Format(' %s %d %d %d %d', [FTypes[i], FWs[i], FHs[i], FOXs[i], FOYs[i]]);
end;

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
