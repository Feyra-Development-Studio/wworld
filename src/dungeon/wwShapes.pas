unit wwShapes;
{ Формы комнат: прямоугольник, эллипс/круг и составная форма (несколько
  намеренно наложенных частей, считающихся одной комнатой).
  Размер составной формы = сумма длинных сторон / больших диаметров частей. }

{$MODE OBJFPC}{$H+}

interface

uses
  Classes, SysUtils, Contnrs, wwCore;

type
  TWwShape = class
  protected
    FW, FH: Integer;
  public
    constructor Create(AW, AH: Integer);
    function Contains(ALX, ALY: Integer): Boolean; virtual; abstract;
    function SizeMetric: Integer; virtual;
    function ShapeName: string; virtual; abstract;
    function CellCount: Integer;
    property W: Integer read FW;
    property H: Integer read FH;
  end;

  TWwRectShape = class(TWwShape)
  public
    function Contains(ALX, ALY: Integer): Boolean; override;
    function ShapeName: string; override;
  end;

  TWwEllipseShape = class(TWwShape)
  public
    function Contains(ALX, ALY: Integer): Boolean; override;
    function ShapeName: string; override;
  end;

  TWwCompositeShape = class(TWwShape)
  private
    FParts: TFPObjectList;
    FOffX, FOffY: array of Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddPart(APart: TWwShape; AOffX, AOffY: Integer);
    procedure Normalize;
    function Contains(ALX, ALY: Integer): Boolean; override;
    function SizeMetric: Integer; override;
    function ShapeName: string; override;
    function PartCount: Integer;
  end;

implementation

{ TWwShape }

constructor TWwShape.Create(AW, AH: Integer);
begin
  inherited Create;
  FW := AW;
  FH := AH;
end;

function TWwShape.SizeMetric: Integer;
begin
  if FW > FH then Result := FW else Result := FH;
end;

function TWwShape.CellCount: Integer;
var
  x, y, n: Integer;
begin
  n := 0;
  for y := 0 to FH - 1 do
    for x := 0 to FW - 1 do
      if Contains(x, y) then Inc(n);
  Result := n;
end;

{ TWwRectShape }

function TWwRectShape.Contains(ALX, ALY: Integer): Boolean;
begin
  Result := (ALX >= 0) and (ALY >= 0) and (ALX < FW) and (ALY < FH);
end;

function TWwRectShape.ShapeName: string;
begin
  if FW = FH then Result := 'square' else Result := 'rect';
end;

{ TWwEllipseShape }

function TWwEllipseShape.Contains(ALX, ALY: Integer): Boolean;
var
  cx, cy, rx, ry, dx, dy: Double;
begin
  if (ALX < 0) or (ALY < 0) or (ALX >= FW) or (ALY >= FH) then
  begin
    Result := False;
    Exit;
  end;
  cx := (FW - 1) / 2.0;
  cy := (FH - 1) / 2.0;
  rx := FW / 2.0;
  ry := FH / 2.0;
  dx := (ALX - cx) / rx;
  dy := (ALY - cy) / ry;
  Result := (dx * dx + dy * dy) <= 1.02;
end;

function TWwEllipseShape.ShapeName: string;
begin
  if FW = FH then Result := 'circle' else Result := 'ellipse';
end;

{ TWwCompositeShape }

constructor TWwCompositeShape.Create;
begin
  inherited Create(0, 0);
  FParts := TFPObjectList.Create(True);
  SetLength(FOffX, 0);
  SetLength(FOffY, 0);
end;

destructor TWwCompositeShape.Destroy;
begin
  FParts.Free;
  inherited Destroy;
end;

procedure TWwCompositeShape.AddPart(APart: TWwShape; AOffX, AOffY: Integer);
begin
  FParts.Add(APart);
  SetLength(FOffX, Length(FOffX) + 1);
  SetLength(FOffY, Length(FOffY) + 1);
  FOffX[High(FOffX)] := AOffX;
  FOffY[High(FOffY)] := AOffY;
end;

procedure TWwCompositeShape.Normalize;
var
  i, minX, minY, maxX, maxY: Integer;
  p: TWwShape;
begin
  if FParts.Count = 0 then Exit;
  minX := FOffX[0];
  minY := FOffY[0];
  maxX := FOffX[0] + TWwShape(FParts[0]).W;
  maxY := FOffY[0] + TWwShape(FParts[0]).H;
  for i := 1 to FParts.Count - 1 do
  begin
    p := TWwShape(FParts[i]);
    if FOffX[i] < minX then minX := FOffX[i];
    if FOffY[i] < minY then minY := FOffY[i];
    if FOffX[i] + p.W > maxX then maxX := FOffX[i] + p.W;
    if FOffY[i] + p.H > maxY then maxY := FOffY[i] + p.H;
  end;
  for i := 0 to FParts.Count - 1 do
  begin
    FOffX[i] := FOffX[i] - minX;
    FOffY[i] := FOffY[i] - minY;
  end;
  FW := maxX - minX;
  FH := maxY - minY;
end;

function TWwCompositeShape.Contains(ALX, ALY: Integer): Boolean;
var
  i: Integer;
  p: TWwShape;
begin
  for i := 0 to FParts.Count - 1 do
  begin
    p := TWwShape(FParts[i]);
    if p.Contains(ALX - FOffX[i], ALY - FOffY[i]) then
    begin
      Result := True;
      Exit;
    end;
  end;
  Result := False;
end;

function TWwCompositeShape.SizeMetric: Integer;
var
  i, s: Integer;
begin
  s := 0;
  for i := 0 to FParts.Count - 1 do
    s := s + TWwShape(FParts[i]).SizeMetric;
  Result := s;
end;

function TWwCompositeShape.ShapeName: string;
begin
  Result := 'composite';
end;

function TWwCompositeShape.PartCount: Integer;
begin
  Result := FParts.Count;
end;

end.
