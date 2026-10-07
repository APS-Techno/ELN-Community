object dlgProtocolReview: TdlgProtocolReview
  Left = 0
  Top = 0
  Caption = 'Protocol Review Queue'
  ClientHeight = 600
  ClientWidth = 1100
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
  object Splitter1: TSplitter
    Left = 400
    Top = 41
    Width = 5
    Height = 514
  end
  object pnlTop: TPanel
    Left = 0
    Top = 0
    Width = 1100
    Height = 41
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object lblFilter: TLabel
      Left = 12
      Top = 12
      Width = 30
      Height = 15
      Caption = 'Filter:'
    end
    object cmbFilter: TComboBox
      Left = 52
      Top = 8
      Width = 160
      Height = 23
      Style = csDropDownList
      TabOrder = 0
      OnChange = cmbFilterChange
    end
    object btnRefresh: TRzButton
      Left = 224
      Top = 7
      Width = 75
      Height = 25
      Caption = 'Refresh'
      TabOrder = 1
      OnClick = btnRefreshClick
    end
  end
  object pnlLeft: TPanel
    Left = 0
    Top = 41
    Width = 400
    Height = 514
    Align = alLeft
    BevelOuter = bvNone
    TabOrder = 1
    object ListView: TListView
      Left = 0
      Top = 0
      Width = 400
      Height = 514
      Align = alClient
      Columns = <
        item
          Caption = 'Protocol Title'
          Width = 200
        end
        item
          Caption = 'Item Title'
          Width = 120
        end
        item
          Caption = 'Created By'
          Width = 80
        end>
      ReadOnly = True
      RowSelect = True
      TabOrder = 0
      ViewStyle = vsReport
      OnDblClick = btnViewClick
      OnSelectItem = ListViewSelectItem
    end
  end
  object pnlPreview: TPanel
    Left = 405
    Top = 41
    Width = 695
    Height = 514
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 2
  end
  object pnlBottom: TRzPanel
    Left = 0
    Top = 555
    Width = 1100
    Height = 45
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 3
    object btnApprove: TRzButton
      Left = 700
      Top = 8
      Width = 90
      Height = 29
      Caption = 'Approve'
      Enabled = False
      TabOrder = 0
      OnClick = btnApproveClick
    end
    object btnReject: TRzButton
      Left = 800
      Top = 8
      Width = 90
      Height = 29
      Caption = 'Reject'
      Enabled = False
      TabOrder = 1
      OnClick = btnRejectClick
    end
    object btnView: TRzButton
      Left = 900
      Top = 8
      Width = 90
      Height = 29
      Caption = 'Edit...'
      Enabled = False
      TabOrder = 2
      OnClick = btnViewClick
    end
    object btnClose: TRzButton
      Left = 1000
      Top = 8
      Width = 90
      Height = 29
      Caption = 'Close'
      Cancel = True
      ModalResult = 2
      TabOrder = 3
    end
  end
end
