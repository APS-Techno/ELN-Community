object frmAnalysis: TfrmAnalysis
  Left = 0
  Top = 0
  Margins.Left = 2
  Margins.Top = 2
  Margins.Right = 2
  Margins.Bottom = 2
  Caption = 'Condition vs Result Analysis'
  ClientHeight = 520
  ClientWidth = 688
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 15
  object pnlToolbar: TRzPanel
    Left = 0
    Top = 0
    Width = 688
    Height = 45
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    Align = alTop
    BorderOuter = fsNone
    TabOrder = 0
    Transparent = True
    Color = clBtnFace
    object lblXAxis: TRzLabel
      Left = 6
      Top = 14
      Width = 31
      Height = 15
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'X Axis'
      Transparent = True
    end
    object lblYAxis: TRzLabel
      Left = 212
      Top = 14
      Width = 31
      Height = 15
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Y Axis'
      Transparent = True
    end
    object cbXAxis: TComboBox
      Left = 43
      Top = 12
      Width = 160
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Style = csDropDownList
      TabOrder = 0
    end
    object cbYAxis: TComboBox
      Left = 249
      Top = 12
      Width = 160
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Style = csDropDownList
      TabOrder = 1
    end
    object btnPlot: TRzBitBtn
      Left = 420
      Top = 9
      Width = 60
      Height = 26
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Plot'
      Enabled = False
      TabOrder = 2
      OnClick = btnPlotClick
      Margin = 1
      Spacing = 2
    end
  end
  object pnlBottom: TRzPanel
    Left = 0
    Top = 480
    Width = 688
    Height = 40
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    Align = alBottom
    BorderOuter = fsNone
    TabOrder = 1
    Transparent = True
    Color = clBtnFace
    object btnCopyData: TRzBitBtn
      Left = 10
      Top = 5
      Width = 111
      Height = 26
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Copy Data (CSV)'
      Enabled = False
      TabOrder = 1
      OnClick = btnCopyDataClick
      Margin = 1
      Spacing = 2
    end
    object btnCopyChart: TRzBitBtn
      Left = 155
      Top = 5
      Width = 80
      Height = 26
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Copy Chart'
      Enabled = False
      TabOrder = 2
      OnClick = btnCopyChartClick
      Margin = 1
      Spacing = 2
    end
    object btnClose: TRzBitBtn
      Left = 622
      Top = 5
      Width = 60
      Height = 26
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      ModalResult = 2
      Caption = 'Close'
      TabOrder = 0
      Margin = 1
      Spacing = 2
    end
  end
  object pnlChart: TRzPanel
    Left = 0
    Top = 45
    Width = 688
    Height = 435
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    Align = alClient
    BorderOuter = fsNone
    TabOrder = 2
    Transparent = True
    Color = clBtnFace
    object RzSplitter1: TRzSplitter
      Left = 0
      Top = 0
      Width = 688
      Height = 435
      Position = 186
      Percent = 27
      UpperLeft.Color = clBtnFace
      LowerRight.Color = clBtnFace
      Align = alClient
      Color = clBtnFace
      TabOrder = 0
      BarSize = (
        186
        0
        190
        435)
      UpperLeftControls = (
        pnlProcs)
      LowerRightControls = (
        chtMain)
      object pnlProcs: TRzPanel
        Left = 0
        Top = 0
        Width = 186
        Height = 435
        Margins.Left = 2
        Margins.Top = 2
        Margins.Right = 2
        Margins.Bottom = 2
        Align = alClient
        BorderOuter = fsNone
        TabOrder = 0
        Transparent = True
        Color = clBtnFace
        object clbProcs: TCheckListBox
          Left = 0
          Top = 0
          Width = 186
          Height = 413
          Margins.Left = 2
          Margins.Top = 2
          Margins.Right = 2
          Margins.Bottom = 2
          Align = alClient
          TabOrder = 0
        end
        object pnlProcBtns: TRzPanel
          Left = 0
          Top = 413
          Width = 186
          Height = 22
          Margins.Left = 2
          Margins.Top = 2
          Margins.Right = 2
          Margins.Bottom = 2
          Align = alBottom
          BorderOuter = fsNone
          TabOrder = 1
          Transparent = True
          Color = clBtnFace
          object btnAll: TRzBitBtn
            Left = 2
            Top = 2
            Width = 50
            Height = 18
            Margins.Left = 2
            Margins.Top = 2
            Margins.Right = 2
            Margins.Bottom = 2
            Caption = 'All'
            TabOrder = 0
            OnClick = btnAllClick
            Margin = 1
            Spacing = 2
          end
          object btnNone: TRzBitBtn
            Left = 56
            Top = 2
            Width = 50
            Height = 18
            Margins.Left = 2
            Margins.Top = 2
            Margins.Right = 2
            Margins.Bottom = 2
            Caption = 'None'
            TabOrder = 1
            OnClick = btnNoneClick
            Margin = 1
            Spacing = 2
          end
        end
      end
      object chtMain: TChart
        Left = 0
        Top = 0
        Width = 498
        Height = 435
        Margins.Left = 2
        Margins.Top = 2
        Margins.Right = 2
        Margins.Bottom = 2
        Legend.ResizeChart = False
        Title.Text.Strings = (
          'Condition vs Result Analysis')
        View3D = False
        View3DOptions.FontZoom = 50
        View3DOptions.PenZoom = 50
        View3DOptions.CheckBoxZoom = 50
        Align = alClient
        TabOrder = 0
        DefaultCanvas = 'TGDIPlusCanvas'
        ColorPaletteIndex = 13
        object serData: TPointSeries
          Marks.Style = smsLabel
          SeriesColor = clBlue
          Title = 'Data points'
          ClickableLine = False
          Pointer.Brush.Color = clBlue
          Pointer.HorizSize = 8
          Pointer.InflateMargins = True
          Pointer.Style = psCircle
          Pointer.VertSize = 8
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
        object serTrend: TLineSeries
          SeriesColor = clRed
          Title = 'Linear trend'
          Brush.BackColor = clDefault
          LinePen.Style = psDash
          LinePen.Width = 4
          Pointer.InflateMargins = True
          Pointer.Style = psRectangle
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
      end
    end
  end
end
