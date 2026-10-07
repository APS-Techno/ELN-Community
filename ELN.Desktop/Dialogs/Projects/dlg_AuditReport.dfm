object dlgAuditReport: TdlgAuditReport
  Left = 0
  Top = 0
  BorderStyle = bsSizeable
  Caption = 'Data Quality Check'
  ClientHeight = 500
  ClientWidth = 880
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 15
  object pnlTop: TPanel
    Left = 0
    Top = 0
    Width = 880
    Height = 70
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object lblTarget: TLabel
      Left = 12
      Top = 8
      Width = 700
      Height = 16
      Caption = ''
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object lblSummary: TLabel
      Left = 12
      Top = 28
      Width = 700
      Height = 16
      Caption = ''
    end
    object lblTimestamp: TLabel
      Left = 12
      Top = 48
      Width = 700
      Height = 16
      Caption = ''
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGray
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
  end
  object pnlBottom: TPanel
    Left = 0
    Top = 460
    Width = 880
    Height = 40
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 1
    object btnGoTo: TButton
      Left = 610
      Top = 8
      Width = 80
      Height = 25
      Anchors = [akTop, akRight]
      Caption = 'Go To'
      TabOrder = 0
      OnClick = btnGoToClick
    end
    object btnExport: TButton
      Left = 700
      Top = 8
      Width = 80
      Height = 25
      Anchors = [akTop, akRight]
      Caption = 'Export...'
      TabOrder = 1
      OnClick = btnExportClick
    end
    object btnClose: TButton
      Left = 790
      Top = 8
      Width = 75
      Height = 25
      Anchors = [akTop, akRight]
      Caption = 'Close'
      ModalResult = 2
      TabOrder = 2
    end
  end
  object lvResults: TListView
    AlignWithMargins = True
    Left = 8
    Top = 72
    Width = 864
    Height = 386
    Margins.Left = 8
    Margins.Top = 2
    Margins.Right = 8
    Margins.Bottom = 2
    Align = alClient
    Columns = <
      item
        Caption = 'Category'
        Width = 65
      end
      item
        Caption = 'Severity'
        Width = 65
      end
      item
        Caption = 'Item'
        Width = 200
      end
      item
        Caption = 'Location'
        Width = 200
      end
      item
        Caption = 'Rule'
        Width = 150
      end
      item
        Caption = 'Missing'
        Width = 150
      end>
    GridLines = True
    HideSelection = False
    ReadOnly = True
    RowSelect = True
    TabOrder = 2
    ViewStyle = vsReport
    OnCustomDrawItem = lvResultsCustomDrawItem
    OnCustomDrawSubItem = lvResultsCustomDrawSubItem
    OnDblClick = lvResultsDblClick
  end
end
