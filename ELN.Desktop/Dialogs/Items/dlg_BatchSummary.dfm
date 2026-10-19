object dlgBatchSummary: TdlgBatchSummary
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Batch'
  ClientHeight = 300
  ClientWidth = 480
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  PixelsPerInch = 96
  TextHeight = 15
  object pnlBottom: TRzPanel
    AlignWithMargins = True
    Left = 8
    Top = 252
    Width = 464
    Height = 40
    Margins.Left = 8
    Margins.Top = 8
    Margins.Right = 8
    Margins.Bottom = 8
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 1
    object btnOk: TRzBitBtn
      Left = 304
      Top = 6
      Width = 80
      Height = 28
      Anchors = [akTop, akRight]
      Caption = 'OK'
      Default = True
      ModalResult = 1
      TabOrder = 0
    end
    object btnCancel: TRzBitBtn
      Left = 392
      Top = 6
      Width = 80
      Height = 28
      Anchors = [akTop, akRight]
      Cancel = True
      Caption = 'Cancel'
      ModalResult = 2
      TabOrder = 1
    end
  end
  object pnlMain: TRzPanel
    AlignWithMargins = True
    Left = 8
    Top = 8
    Width = 464
    Height = 244
    Margins.Left = 8
    Margins.Top = 8
    Margins.Right = 8
    Margins.Bottom = 0
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 0
    object lblMessage: TRzLabel
      AlignWithMargins = True
      Left = 9
      Top = 9
      Width = 446
      Height = 36
      Align = alTop
      AutoSize = False
      Caption = 'lblMessage'
      WordWrap = True
    end
    object memDetails: TMemo
      AlignWithMargins = True
      Left = 9
      Top = 51
      Width = 446
      Height = 184
      Align = alClient
      ReadOnly = True
      ScrollBars = ssBoth
      TabOrder = 0
      WordWrap = False
    end
  end
end
