object dlgHypothesisPick: TdlgHypothesisPick
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Attach to hypothesis'
  ClientHeight = 360
  ClientWidth = 460
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poOwnerFormCenter
  TextHeight = 15
  object lblHint: TLabel
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 454
    Height = 15
    Align = alTop
    Caption = 'Hypotheses in this project'
  end
  object lstHypotheses: TListBox
    AlignWithMargins = True
    Left = 3
    Top = 24
    Width = 454
    Height = 230
    Align = alClient
    ItemHeight = 15
    TabOrder = 0
    OnClick = lstHypothesesClick
    OnDblClick = lstHypothesesDblClick
  end
  object rgRole: TRadioGroup
    AlignWithMargins = True
    Left = 3
    Top = 260
    Width = 454
    Height = 54
    Align = alBottom
    Caption = 'Attach as'
    Columns = 2
    ItemIndex = 0
    Items.Strings = (
      'Run (made to test it)'
      'Reference (for comparison)')
    TabOrder = 1
  end
  object pnlButtons: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 320
    Width = 454
    Height = 37
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 2
    object btnOK: TButton
      Left = 262
      Top = 5
      Width = 90
      Height = 27
      Caption = 'Attach'
      Default = True
      ModalResult = 1
      TabOrder = 0
    end
    object btnCancel: TButton
      Left = 358
      Top = 5
      Width = 90
      Height = 27
      Cancel = True
      Caption = 'Cancel'
      ModalResult = 2
      TabOrder = 1
    end
  end
end
