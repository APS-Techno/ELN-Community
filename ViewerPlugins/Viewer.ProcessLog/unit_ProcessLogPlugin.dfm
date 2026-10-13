object ELNProcessLogViewerPlugin: TELNProcessLogViewerPlugin
  OnCreate = upfVisualPluginCreate
  OnDestroy = upfVisualPluginDestroy
  PluginID = '7072'
  PluginName = 'Process Log Viewer'
  Author = 'APS Technology'
  Description = 'Deposition process event log (.process.log) viewer'
  Commands = <>
  Version = '6.13.0'
  Height = 590
  Width = 839
  PixelsPerInch = 192
end
