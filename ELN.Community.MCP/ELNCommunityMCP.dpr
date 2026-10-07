program ELNCommunityMCP;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Vcl.Forms,
  unit_CommunityMCPHost in 'unit_CommunityMCPHost.pas',
  unit_MCPTransport in '..\ELN.MCPServer\unit_MCPTransport.pas',
  unit_ToolDownloads in '..\ELN.MCPServer\unit_ToolDownloads.pas',
  unit_DomainEntities in '..\ELN.Domain\unit_DomainEntities.pas';

begin
  Application.Initialize;
  try
    RunCommunityServer;
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, 'Fatal: ' + E.Message);
      Flush(ErrOutput);
      ExitCode := 1;
    end;
  end;
end.
