unit unit_ToolCatalog;

{ Register new tool groups here, not in individual hosts, so every host uses
  the same catalog. }

interface

uses
  unit_MCPTools;

procedure RegisterAllTools(Registry: TToolRegistry);

implementation

uses
  unit_ToolsNavigation,
  unit_ToolsValues,
  unit_ToolsFiles,
  unit_ToolsMetadata,
  unit_ToolsWrite,
  unit_ToolsWiki,
  unit_ToolsColumnar,
  unit_ToolsTags,
  unit_ToolsHypotheses;

procedure RegisterAllTools(Registry: TToolRegistry);
begin
  RegisterNavigationTools(Registry);
  RegisterValueTools(Registry);
  RegisterFileTools(Registry);
  RegisterMetadataTools(Registry);
  RegisterWriteTools(Registry);
  RegisterWikiTools(Registry);
  RegisterColumnarTools(Registry);
  RegisterTagTools(Registry);
  RegisterHypothesisTools(Registry);
end;

end.
