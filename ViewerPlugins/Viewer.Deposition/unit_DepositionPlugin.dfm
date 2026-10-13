object ELNDepositionViewerPlugin: TELNDepositionViewerPlugin
  OnCreate = upfVisualPluginCreate
  OnDestroy = upfVisualPluginDestroy
  PluginID = '7070'
  PluginName = 'Deposition Viewer'
  Author = 'APS Technology'
  Description = 'Deposition run viewer (TSV log + depo.json snapshot)'
  Copyright = '2026'
  Commands = <>
  Version = '1.0.0'
  Height = 762
  Width = 993
  PixelsPerInch = 192
end
