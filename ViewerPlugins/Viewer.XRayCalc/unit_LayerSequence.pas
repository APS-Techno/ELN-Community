unit unit_LayerSequence;


interface

uses
  System.SysUtils, System.JSON, unit_XRCProject;

function BuildLayerSequenceJSON(const Model: TXRCModel): TJSONArray;

implementation

uses
  unit_ELNPluginTypes;

function BuildLayerSequenceJSON(const Model: TXRCModel): TJSONArray;
var
  S, P, L, I: Integer;
  Obj: TJSONObject;
  Layer: TXRCLayer;
begin
  Result := TJSONArray.Create;
  try
    I := 0;
    for S := 0 to High(Model.Stacks) do
      for P := 1 to Model.Stacks[S].N do
        for L := 0 to High(Model.Stacks[S].Layers) do
        begin
          Layer := Model.Stacks[S].Layers[L];
          Obj := TJSONObject.Create;
          Result.AddElement(Obj);
          Obj.AddPair('i', TJSONNumber.Create(I));
          Obj.AddPair('stack', TJSONNumber.Create(S));
          Obj.AddPair('period', TJSONNumber.Create(P));
          Obj.AddPair('material', Layer.Material);
          Obj.AddPair('h_A', JNum(XRCProfileValue(Layer, xpThickness, P)));
          Obj.AddPair('sigma_A', JNum(XRCProfileValue(Layer, xpRoughness, P)));
          Obj.AddPair('rho_gcm3', JNum(XRCProfileValue(Layer, xpDensity, P)));
          Inc(I);
        end;

    if Model.SubsMaterial <> '' then
    begin
      Obj := TJSONObject.Create;
      Result.AddElement(Obj);
      Obj.AddPair('i', TJSONNumber.Create(I));
      Obj.AddPair('substrate', TJSONBool.Create(True));
      Obj.AddPair('material', Model.SubsMaterial);
      Obj.AddPair('sigma_A', JNum(Model.SubsSigma));
      Obj.AddPair('rho_gcm3', JNum(Model.SubsRho));
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
