object dlgSeriesLink: TdlgSeriesLink
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Link to plan point'
  ClientHeight = 460
  ClientWidth = 520
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poOwnerFormCenter
  OnCloseQuery = FormCloseQuery
  TextHeight = 15
  object lblSeries: TLabel
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 514
    Height = 15
    Align = alTop
    Caption = 'Active series in this project'
  end
  object lstSeries: TListBox
    AlignWithMargins = True
    Left = 3
    Top = 24
    Width = 514
    Height = 100
    Align = alTop
    ItemHeight = 15
    TabOrder = 0
    OnClick = lstSeriesClick
  end
  object lblPoint: TLabel
    AlignWithMargins = True
    Left = 3
    Top = 130
    Width = 514
    Height = 15
    Align = alTop
    Caption = 'Plan point'
  end
  object cmbPoint: TComboBox
    AlignWithMargins = True
    Left = 3
    Top = 151
    Width = 514
    Height = 23
    Align = alTop
    Style = csDropDownList
    TabOrder = 1
    OnChange = cmbPointChange
  end
  object chkNew: TCheckBox
    AlignWithMargins = True
    Left = 3
    Top = 180
    Width = 514
    Height = 21
    Align = alTop
    Caption = 'Add new points for depositions that match no point'
    TabOrder = 2
    OnClick = chkNewClick
  end
  object lblPreview: TLabel
    AlignWithMargins = True
    Left = 3
    Top = 207
    Width = 514
    Height = 15
    Align = alTop
    Caption = 'What will happen'
  end
  object pnlButtons: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 420
    Width = 514
    Height = 37
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 4
    object btnOK: TButton
      Left = 322
      Top = 5
      Width = 90
      Height = 27
      Caption = 'Link'
      Default = True
      ModalResult = 1
      TabOrder = 0
    end
    object btnCancel: TButton
      Left = 418
      Top = 5
      Width = 90
      Height = 27
      Cancel = True
      Caption = 'Cancel'
      ModalResult = 2
      TabOrder = 1
    end
  end
  object lstPreview: TListBox
    AlignWithMargins = True
    Left = 3
    Top = 228
    Width = 514
    Height = 186
    Align = alClient
    ItemHeight = 15
    TabOrder = 3
  end
end
