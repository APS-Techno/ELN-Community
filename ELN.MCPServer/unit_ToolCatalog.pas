unit unit_ToolCatalog;

{ The ONE list of tool groups this server registers. RunServer and
  ELN.Tests\test_ToolRegistryGates both call RegisterAllTools, so a tool added
  to any group is automatically driven by the gate test (experiment tree,
  spec section 11 C3(b)). Add new groups here, never directly in RunServer. }

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
