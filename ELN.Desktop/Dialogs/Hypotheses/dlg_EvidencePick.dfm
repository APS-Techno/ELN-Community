object dlgEvidencePick: TdlgEvidencePick
  Left = 0
  Top = 0
  BorderStyle = bsSizeable
  Caption = 'Cite evidence'
  ClientHeight = 420
  ClientWidth = 640
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poOwnerFormCenter
  TextHeight = 15
  object lstItems: TListBox
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 250
    Height = 334
    Align = alLeft
    ItemHeight = 15
    TabOrder = 0
    OnClick = lstItemsClick
  end
  object lstChoices: TListBox
    AlignWithMargins = True
    Left = 259
    Top = 3
    Width = 378
    Height = 334
    Align = alClient
    ItemHeight = 15
    TabOrder = 1
  end
  object pnlBottom: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 343
    Width = 634
    Height = 74
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 2
    object lblNote: TLabel
      Left = 8
      Top = 8
      Width = 200
      Height = 15
      Caption = 'Note (optional)'
    end
    object edNote: TEdit
      Left = 8
      Top = 28
      Width = 420
      Height = 23
      MaxLength = 500
      TabOrder = 0
    end
    object btnOK: TButton
      Left = 440
      Top = 26
      Width = 90
      Height = 27
      Caption = 'Cite'
      Default = True
      TabOrder = 1
      OnClick = btnOKClick
    end
    object btnCancel: TButton
      Left = 536
      Top = 26
      Width = 90
      Height = 27
      Cancel = True
      Caption = 'Cancel'
      ModalResult = 2
      TabOrder = 2
    end
  end
end
