object frameSeries: TframeSeries
  Left = 0
  Top = 0
  Width = 900
  Height = 640
  Align = alClient
  TabOrder = 0
  object pnlToolbar: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 894
    Height = 76
    Align = alTop
    AutoSize = True
    BorderOuter = fsFlatRounded
    TabOrder = 0
    object lblProject: TLabel
      AlignWithMargins = True
      Left = 9
      Top = 4
      Width = 880
      Height = 22
      Margins.Left = 8
      Align = alTop
      AutoSize = False
      Caption = 'Series'
      EllipsisPosition = epEndEllipsis
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
      Layout = tlCenter
    end
    object flpButtons: TFlowPanel
      AlignWithMargins = True
      Left = 9
      Top = 30
      Width = 876
      Height = 36
      Margins.Left = 8
      Margins.Top = 0
      Margins.Bottom = 0
      Align = alTop
      AutoSize = True
      BevelOuter = bvNone
      ParentBackground = True
      TabOrder = 0
      object btnNew: TButton
        AlignWithMargins = True
        Left = 3
        Top = 3
        Width = 100
        Height = 27
        Hint = 'Plan a new series in this project'
        Caption = 'New series...'
        ParentShowHint = False
        ShowHint = True
        TabOrder = 0
        OnClick = btnNewClick
      end
      object btnEdit: TButton
        AlignWithMargins = True
        Left = 109
        Top = 3
        Width = 90
        Height = 27
        Hint = 'Change the title, purpose, factors, fixed conditions or responses of the selected series'
        Caption = 'Edit plan...'
        ParentShowHint = False
        ShowHint = True
        TabOrder = 1
        OnClick = btnEditClick
      end
      object btnAddPoint: TButton
        AlignWithMargins = True
        Left = 205
        Top = 3
        Width = 90
        Height = 27
        Hint = 'Add one more point and make its deposition'
        Caption = 'Add point...'
        ParentShowHint = False
        ShowHint = True
        TabOrder = 2
        OnClick = btnAddPointClick
      end
      object btnStatus: TButton
        AlignWithMargins = True
        Left = 301
        Top = 3
        Width = 70
        Height = 27
        Hint = 'Start a draft series, close a series when the work is done, or reopen it'
        Caption = 'Close'
        ParentShowHint = False
        ShowHint = True
        TabOrder = 3
        OnClick = btnStatusClick
      end
      object btnAbandon: TButton
        AlignWithMargins = True
        Left = 377
        Top = 3
        Width = 90
        Height = 27
        Hint = 'Stop work on this series. It stays in the list as Abandoned.'
        Caption = 'Abandon...'
        ParentShowHint = False
        ShowHint = True
        TabOrder = 4
        OnClick = btnAbandonClick
      end
      object chkShowFailed: TCheckBox
        AlignWithMargins = True
        Left = 473
        Top = 3
        Width = 90
        Height = 27
        Caption = 'Show failed'
        TabOrder = 5
        OnClick = chkShowFailedClick
      end
      object btnRefresh: TButton
        AlignWithMargins = True
        Left = 569
        Top = 3
        Width = 70
        Height = 27
        Hint = 'Load the latest changes, including those made by others'
        Caption = 'Refresh'
        ParentShowHint = False
        ShowHint = True
        TabOrder = 6
        OnClick = btnRefreshClick
      end
      object btnCopy: TButton
        AlignWithMargins = True
        Left = 645
        Top = 3
        Width = 90
        Height = 27
        Hint = 'Copy the table as tab-separated text, ready to paste into Origin'
        Caption = 'Copy table'
        ParentShowHint = False
        ShowHint = True
        TabOrder = 7
        OnClick = btnCopyClick
      end
      object btnSaveCsv: TButton
        AlignWithMargins = True
        Left = 741
        Top = 3
        Width = 100
        Height = 27
        Hint = 'Save the table as a CSV file'
        Caption = 'Save CSV...'
        ParentShowHint = False
        ShowHint = True
        TabOrder = 8
        OnClick = btnSaveCsvClick
      end
      object btnRemoveExcluded: TButton
        AlignWithMargins = True
        Left = 3
        Top = 36
        Width = 120
        Height = 27
        Hint = 'Unlink the depositions that are in the recycle bin or another project from the series'
        Caption = 'Unlink excluded'
        ParentShowHint = False
        ShowHint = True
        TabOrder = 9
        Visible = False
        OnClick = btnRemoveExcludedClick
      end
    end
  end
  object pnlStatus: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 610
    Width = 894
    Height = 27
    Align = alBottom
    AutoSize = True
    BorderOuter = fsFlatRounded
    TabOrder = 1
    object lblStatus: TLabel
      AlignWithMargins = True
      Left = 9
      Top = 4
      Width = 878
      Height = 19
      Margins.Left = 8
      Align = alTop
      AutoSize = False
      EllipsisPosition = epEndEllipsis
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGrayText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Layout = tlCenter
    end
  end
  object vstSeries: TVirtualStringTree
    AlignWithMargins = True
    Left = 3
    Top = 80
    Width = 300
    Height = 537
    Align = alLeft
    DefaultNodeHeight = 26
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    Header.AutoSizeIndex = 0
    Header.Font.Charset = DEFAULT_CHARSET
    Header.Font.Color = clWindowText
    Header.Font.Height = -12
    Header.Font.Name = 'Segoe UI'
    Header.Font.Style = []
    Header.Height = 21
    Header.Options = [hoAutoResize, hoColumnResize, hoVisible]
    Header.ParentFont = False
    ParentFont = False
    TabOrder = 1
    TreeOptions.SelectionOptions = [toFullRowSelect]
    OnAfterCellPaint = TreeAfterCellPaint
    OnBeforeCellPaint = TreeBeforeCellPaint
    OnFocusChanged = vstSeriesFocusChanged
    OnGetCellText = vstSeriesGetCellText
    OnGetNodeDataSize = vstSeriesGetNodeDataSize
    Columns = <
      item
        Position = 0
        Text = 'Series'
        Width = 130
      end
      item
        Position = 1
        Text = 'Status'
        Width = 70
      end
      item
        Position = 2
        Text = 'Progress'
        Width = 100
      end>
  end
  object splMain: TSplitter
    Left = 306
    Top = 77
    Width = 5
    Height = 543
  end
  object pcMain: TPageControl
    AlignWithMargins = True
    Left = 314
    Top = 80
    Width = 583
    Height = 537
    ActivePage = tsTable
    Align = alClient
    TabOrder = 2
    OnChange = pcMainChange
    object tsTable: TTabSheet
      Caption = 'Table'
      object lblEmpty: TLabel
        AlignWithMargins = True
        Left = 3
        Top = 3
        Width = 569
        Height = 38
        Align = alTop
        AutoSize = False
        Caption = 'No series yet. Click New series... to make one.'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGrayText
        Font.Height = -13
        Font.Name = 'Segoe UI'
        Font.Style = []
        ParentFont = False
        Layout = tlCenter
        Visible = False
        WordWrap = True
      end
      object vstTable: TVirtualStringTree
        AlignWithMargins = True
        Left = 3
        Top = 26
        Width = 569
        Height = 480
        Align = alClient
        DefaultNodeHeight = 24
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = []
        Header.Font.Charset = DEFAULT_CHARSET
        Header.Font.Color = clWindowText
        Header.Font.Height = -12
        Header.Font.Name = 'Segoe UI'
        Header.Font.Style = []
        Header.Height = 36
        Header.Options = [hoColumnResize, hoVisible, hoShowHint]
        HintMode = hmHint
        Header.ParentFont = False
        ParentFont = False
        ParentShowHint = False
        ShowHint = True
        TabOrder = 0
        TreeOptions.SelectionOptions = [toFullRowSelect]
        OnAfterCellPaint = TreeAfterCellPaint
        OnBeforeCellPaint = TreeBeforeCellPaint
        OnFocusChanged = vstTableFocusChanged
        OnGetCellText = vstTableGetCellText
        OnGetNodeDataSize = vstSeriesGetNodeDataSize
        OnGetHint = vstTableGetHint
        OnHeaderMouseUp = vstTableHeaderMouseUp
        OnMouseUp = vstTableMouseUp
        OnNodeDblClick = vstTableNodeDblClick
        OnPaintText = vstTablePaintText
        Columns = <>
      end
    end
    object tsPlot: TTabSheet
      Caption = 'Plot'
      ImageIndex = 1
      object pnlPlotOptions: TRzPanel
        AlignWithMargins = True
        Left = 3
        Top = 3
        Width = 200
        Height = 503
        Align = alLeft
        BorderOuter = fsFlatRounded
        TabOrder = 0
        object lblX: TLabel
          AlignWithMargins = True
          Left = 5
          Top = 5
          Width = 190
          Height = 15
          Align = alTop
          Caption = 'X (condition)'
        end
        object cbX: TComboBox
          AlignWithMargins = True
          Left = 5
          Top = 23
          Width = 190
          Height = 23
          Align = alTop
          Style = csDropDownList
          TabOrder = 0
          OnChange = PlotOptionChange
        end
        object lblGroup: TLabel
          AlignWithMargins = True
          Left = 5
          Top = 49
          Width = 190
          Height = 15
          Align = alTop
          Caption = 'Group by (condition)'
        end
        object cbGroup: TComboBox
          AlignWithMargins = True
          Left = 5
          Top = 67
          Width = 190
          Height = 23
          Align = alTop
          Style = csDropDownList
          TabOrder = 1
          OnChange = PlotOptionChange
        end
        object chkTrend: TCheckBox
          AlignWithMargins = True
          Left = 5
          Top = 93
          Width = 190
          Height = 19
          Align = alTop
          Caption = 'Linear trend'
          TabOrder = 2
          OnClick = PlotOptionChange
        end
        object lblY: TLabel
          AlignWithMargins = True
          Left = 5
          Top = 115
          Width = 190
          Height = 15
          Align = alTop
          Caption = 'Y (results)'
        end
        object lblPlotNote: TLabel
          AlignWithMargins = True
          Left = 5
          Top = 425
          Width = 190
          Height = 73
          Align = alBottom
          AutoSize = False
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clGrayText
          Font.Height = -12
          Font.Name = 'Segoe UI'
          Font.Style = []
          ParentFont = False
          WordWrap = True
        end
        object clbY: TCheckListBox
          AlignWithMargins = True
          Left = 5
          Top = 133
          Width = 190
          Height = 286
          OnClickCheck = PlotOptionChange
          Align = alClient
          ItemHeight = 17
          TabOrder = 3
        end
      end
      object pnlPlot: TRzPanel
        AlignWithMargins = True
        Left = 209
        Top = 3
        Width = 363
        Height = 503
        Align = alClient
        BorderOuter = fsFlatRounded
        TabOrder = 1
        object chtPlot: TChart
          AlignWithMargins = True
          Left = 5
          Top = 5
          Width = 353
          Height = 493
          Legend.ResizeChart = False
          Title.Text.Strings = (
            'Series')
          View3D = False
          OnAfterDraw = chtPlotAfterDraw
          Align = alClient
          BevelOuter = bvNone
          TabOrder = 0
          DefaultCanvas = 'TGDIPlusCanvas'
          ColorPaletteIndex = 13
          object serGroup1: TLineSeries
            Brush.BackColor = clDefault
            Pointer.HorizSize = 4
            Pointer.InflateMargins = True
            Pointer.Style = psCircle
            Pointer.VertSize = 4
            Pointer.Visible = True
            XValues.Name = 'X'
            XValues.Order = loAscending
            YValues.Name = 'Y'
            YValues.Order = loNone
          end
          object serGroup2: TLineSeries
            Brush.BackColor = clDefault
            Pointer.HorizSize = 4
            Pointer.InflateMargins = True
            Pointer.Style = psCircle
            Pointer.VertSize = 4
            Pointer.Visible = True
            XValues.Name = 'X'
            XValues.Order = loAscending
            YValues.Name = 'Y'
            YValues.Order = loNone
          end
          object serGroup3: TLineSeries
            Brush.BackColor = clDefault
            Pointer.HorizSize = 4
            Pointer.InflateMargins = True
            Pointer.Style = psCircle
            Pointer.VertSize = 4
            Pointer.Visible = True
            XValues.Name = 'X'
            XValues.Order = loAscending
            YValues.Name = 'Y'
            YValues.Order = loNone
          end
          object serGroup4: TLineSeries
            Brush.BackColor = clDefault
            Pointer.HorizSize = 4
            Pointer.InflateMargins = True
            Pointer.Style = psCircle
            Pointer.VertSize = 4
            Pointer.Visible = True
            XValues.Name = 'X'
            XValues.Order = loAscending
            YValues.Name = 'Y'
            YValues.Order = loNone
          end
          object serGroup5: TLineSeries
            Brush.BackColor = clDefault
            Pointer.HorizSize = 4
            Pointer.InflateMargins = True
            Pointer.Style = psCircle
            Pointer.VertSize = 4
            Pointer.Visible = True
            XValues.Name = 'X'
            XValues.Order = loAscending
            YValues.Name = 'Y'
            YValues.Order = loNone
          end
          object serGroup6: TLineSeries
            Brush.BackColor = clDefault
            Pointer.HorizSize = 4
            Pointer.InflateMargins = True
            Pointer.Style = psCircle
            Pointer.VertSize = 4
            Pointer.Visible = True
            XValues.Name = 'X'
            XValues.Order = loAscending
            YValues.Name = 'Y'
            YValues.Order = loNone
          end
          object serGroup7: TLineSeries
            Brush.BackColor = clDefault
            Pointer.HorizSize = 4
            Pointer.InflateMargins = True
            Pointer.Style = psCircle
            Pointer.VertSize = 4
            Pointer.Visible = True
            XValues.Name = 'X'
            XValues.Order = loAscending
            YValues.Name = 'Y'
            YValues.Order = loNone
          end
          object serGroup8: TLineSeries
            Brush.BackColor = clDefault
            Pointer.HorizSize = 4
            Pointer.InflateMargins = True
            Pointer.Style = psCircle
            Pointer.VertSize = 4
            Pointer.Visible = True
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
            LinePen.Width = 2
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
  object pmRole: TPopupMenu
    Left = 560
    Top = 120
    object miRoleShown: TMenuItem
      Caption = 'Shown'
      OnClick = miRoleClick
    end
    object miRoleHidden: TMenuItem
      Caption = 'Hidden'
      Tag = 1
      OnClick = miRoleClick
    end
    object miRoleVaried: TMenuItem
      Caption = 'Varied'
      Tag = 2
      OnClick = miRoleClick
    end
    object miRoleResponse: TMenuItem
      Caption = 'Response'
      Tag = 3
      OnClick = miRoleClick
    end
  end
  object pmRow: TPopupMenu
    Images = dmTreeImages.vilMenuImages
    Left = 640
    Top = 120
    object miMake: TMenuItem
      Caption = 'Make deposition...'
      ImageIndex = 21
      OnClick = miMakeClick
    end
    object miLink: TMenuItem
      Caption = 'Link existing deposition...'
      ImageIndex = 71
      OnClick = miLinkClick
    end
    object miOpen: TMenuItem
      Caption = 'Open deposition'
      ImageIndex = 64
      OnClick = miOpenClick
    end
    object miConfirm: TMenuItem
      Caption = 'Confirm planned values'
      ImageIndex = 72
      OnClick = miConfirmClick
    end
    object miFail: TMenuItem
      Caption = 'Mark failed...'
      ImageIndex = 73
      OnClick = miFailClick
    end
    object miUnlink: TMenuItem
      Caption = 'Unlink deposition'
      ImageIndex = 74
      OnClick = miUnlinkClick
    end
    object miRemovePoint: TMenuItem
      Caption = 'Remove point'
      ImageIndex = 75
      OnClick = miRemovePointClick
    end
  end
  object dlgSave: TFileSaveDialog
    DefaultExtension = 'csv'
    FavoriteLinks = <>
    FileTypes = <
      item
        DisplayName = 'CSV files (*.csv)'
        FileMask = '*.csv'
      end>
    Left = 600
    Top = 120
  end
end
