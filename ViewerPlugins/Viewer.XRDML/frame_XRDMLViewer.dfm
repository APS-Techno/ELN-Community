object frameXRDMLViewer: TframeXRDMLViewer
  Left = 0
  Top = 0
  Width = 1776
  Height = 1242
  Margins.Left = 6
  Margins.Top = 6
  Margins.Right = 6
  Margins.Bottom = 6
  TabOrder = 0
  PixelsPerInch = 192
  object Status: TRzStatusBar
    Left = 0
    Top = 1204
    Width = 1776
    Height = 38
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    BevelWidth = 2
    BorderInner = fsNone
    BorderOuter = fsNone
    BorderSides = [sdLeft, sdTop, sdRight, sdBottom]
    BorderWidth = 0
    Color = 15987699
    TabOrder = 0
  end
  object Chart: TChart
    AlignWithMargins = True
    Left = 6
    Top = 6
    Width = 1764
    Height = 1192
    Cursor = crCross
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Foot.Visible = False
    Legend.Brush.Color = clSilver
    Legend.Brush.BackColor = clSilver
    Legend.Brush.Gradient.Direction = gdTopBottom
    Legend.Brush.Gradient.EndColor = 2152289
    Legend.Brush.Gradient.MidColor = 7548915
    Legend.Brush.Gradient.StartColor = 10109259
    Legend.Color = 14210754
    Legend.Font.Height = -13
    Legend.Font.Style = [fsBold]
    Legend.Frame.Width = 2
    Legend.Frame.Visible = False
    Legend.LegendStyle = lsSeries
    Legend.ResizeChart = False
    Legend.Shadow.Color = 9211020
    Legend.ShapeStyle = fosRoundRectangle
    Legend.TextStyle = ltsPlain
    Legend.Title.Transparent = False
    Legend.TopPos = 3
    Legend.Visible = False
    MarginBottom = 2
    MarginLeft = 30
    MarginRight = 2
    MarginTop = 2
    MarginUnits = muPixels
    PrintProportional = False
    SubFoot.Visible = False
    SubTitle.Visible = False
    Title.Alignment = taLeftJustify
    Title.Text.Strings = (
      'TChart')
    Title.Visible = False
    BottomAxis.LabelsFormat.Font.Height = -13
    BottomAxis.MinorTicks.Visible = False
    BottomAxis.TickInnerLength = 5
    BottomAxis.TickLength = 0
    BottomAxis.Ticks.Width = 2
    BottomAxis.TicksInner.Width = 2
    BottomAxis.Title.Caption = 'Incidence angle (deg)'
    BottomAxis.Title.Font.Height = -16
    BottomAxis.Title.Pen.Visible = False
    DepthAxis.Automatic = False
    DepthAxis.AutomaticMaximum = False
    DepthAxis.AutomaticMinimum = False
    DepthAxis.Maximum = 0.439999999999999900
    DepthAxis.Minimum = -0.560000000000000300
    DepthTopAxis.Automatic = False
    DepthTopAxis.AutomaticMaximum = False
    DepthTopAxis.AutomaticMinimum = False
    DepthTopAxis.Maximum = 0.439999999999999900
    DepthTopAxis.Minimum = -0.560000000000000300
    LeftAxis.Axis.SmallSpace = 1
    LeftAxis.AxisValuesFormat = '0x10E-0'
    LeftAxis.LabelsExponent = True
    LeftAxis.LabelsFormat.Font.Height = -13
    LeftAxis.LabelsFormat.Margins.Left = 0
    LeftAxis.LabelsFormat.Margins.Top = 0
    LeftAxis.LabelsFormat.Margins.Right = 0
    LeftAxis.LabelsFormat.Margins.Bottom = 0
    LeftAxis.LabelsFormat.Margins.Units = maPixels
    LeftAxis.Logarithmic = True
    LeftAxis.MaximumOffset = 5
    LeftAxis.MinorTicks.Visible = False
    LeftAxis.RoundFirstLabel = False
    LeftAxis.TickInnerLength = 5
    LeftAxis.TickLength = 0
    LeftAxis.TicksInner.Width = 2
    LeftAxis.Title.Caption = 'Intensity (cps)'
    LeftAxis.Title.Font.Height = -16
    LeftAxis.TitleSize = 15
    Pages.AutoScale = True
    RightAxis.Automatic = False
    RightAxis.AutomaticMaximum = False
    RightAxis.AutomaticMinimum = False
    RightAxis.Labels = False
    RightAxis.LabelsFormat.Visible = False
    RightAxis.LabelsOnAxis = False
    RightAxis.Logarithmic = True
    RightAxis.Maximum = 1.000000000000000000
    RightAxis.Minimum = 0.000001000000000000
    RightAxis.RoundFirstLabel = False
    TopAxis.Labels = False
    TopAxis.LabelsFormat.Visible = False
    View3D = False
    View3DOptions.FontZoom = 200
    View3DOptions.PenZoom = 200
    View3DOptions.CheckBoxZoom = 200
    Zoom.Pen.Color = clRed
    Zoom.Pen.Mode = pmNotXor
    Align = alClient
    BevelOuter = bvLowered
    Color = clCream
    TabOrder = 1
    DesignSize = (
      1764
      1192)
    DefaultCanvas = 'TGDIPlusCanvas'
    PrintMargins = (
      5
      5
      5
      5)
    ColorPaletteIndex = 13
    object btnCopy: TRzBitBtn
      Left = 1504
      Top = 16
      Width = 242
      Height = 50
      Margins.Left = 6
      Margins.Top = 6
      Margins.Right = 6
      Margins.Bottom = 6
      Anchors = [akTop, akRight]
      Caption = 'Copy to clipboard'
      TabOrder = 0
      OnClick = btnCopyClick
      Margin = 4
      Spacing = 8
    end
    object btnSave: TRzBitBtn
      Left = 1504
      Top = 78
      Width = 242
      Height = 50
      Margins.Left = 6
      Margins.Top = 6
      Margins.Right = 6
      Margins.Bottom = 6
      Anchors = [akTop, akRight]
      Caption = 'Save to File'
      TabOrder = 1
      OnClick = btnSaveClick
      Margin = 4
      Spacing = 8
    end
    object Series1: TFastLineSeries
      LinePen.Color = clGreen
      LinePen.Width = 3
      XValues.Name = 'X'
      XValues.Order = loAscending
      YValues.Name = 'Y'
      YValues.Order = loNone
    end
  end
  object dlgSave: TSaveDialog
    DefaultExt = '.dat'
    Filter = 'DAT (ASCII)|*.dat|TXT|*.txt'
    Left = 400
    Top = 300
  end
end
