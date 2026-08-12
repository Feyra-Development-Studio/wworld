program demo;

{$mode objfpc}{$H+}

uses
  SysUtils, DungeonGenerator;

var
  Gen: TDungeonGenerator;
begin
  try
    Gen := TDungeonGenerator.Create(12345);
    try
      if Gen.Generate(1) then
        Writeln('geometry.json generated successfully')
      else
        Writeln('generation failed');
    finally
      Gen.Free;
    end;
  except
    on E: Exception do
      Writeln('Error: ', E.ClassName, ' - ', E.Message);
  end;
end.
