object dlgNewFromTemplate: TdlgNewFromTemplate
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'New Experiment from Template'
  ClientHeight = 600
  ClientWidth = 900
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  TextHeight = 15
  object spltMain: TSplitter
    Left = 505
    Top = 0
    Height = 560
    ExplicitLeft = 250
  end
  object pnlBottom: TRzPanel
    Left = 0
    Top = 560
    Width = 900
    Height = 40
    Align = alBottom
    BorderOuter = fsNone
    TabOrder = 0
    Color = clBtnFace
    DesignSize = (
      900
      40)
    object btnCancel: TRzButton
      Left = 810
      Top = 6
      Width = 80
      Cancel = True
      ModalResult = 2
      Anchors = [akTop, akRight]
      Caption = 'Cancel'
      TabOrder = 1
    end
    object btnCreate: TRzButton
      Left = 722
      Top = 6
      Width = 80
      Anchors = [akTop, akRight]
      Caption = 'Create'
      TabOrder = 0
      OnClick = btnCreateClick
    end
  end
  object pnlLeft: TRzPanel
    Left = 0
    Top = 0
    Width = 505
    Height = 560
    Align = alLeft
    BorderOuter = fsNone
    TabOrder = 1
    Color = clBtnFace
    object scrTemplates: TScrollBox
      AlignWithMargins = True
      Left = 3
      Top = 3
      Width = 499
      Height = 554
      Align = alClient
      BorderStyle = bsNone
      TabOrder = 0
      ExplicitLeft = 0
      ExplicitTop = 0
      ExplicitWidth = 250
      ExplicitHeight = 560
    end
  end
  object pnlRight: TRzPanel
    Left = 508
    Top = 0
    Width = 392
    Height = 560
    Align = alClient
    BorderOuter = fsNone
    TabOrder = 2
    Color = clBtnFace
    ExplicitLeft = 253
    ExplicitWidth = 647
    object pnlTitleBar: TRzPanel
      Left = 0
      Top = 524
      Width = 392
      Height = 36
      Align = alBottom
      BorderOuter = fsNone
      TabOrder = 1
      Color = clBtnFace
      ExplicitWidth = 647
      DesignSize = (
        392
        36)
      object lblTitle: TRzLabel
        Left = 31
        Top = 12
        Width = 85
        Height = 15
        Caption = 'Experiment title:'
        Transparent = True
      end
      object edtTitle: TRzEdit
        Left = 122
        Top = 9
        Width = 264
        Height = 23
        Text = ''
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 0
      end
    end
    object vstPreview: TVirtualStringTree
      AlignWithMargins = True
      Left = 3
      Top = 3
      Width = 386
      Height = 518
      Align = alClient
      DefaultNodeHeight = 19
      Header.AutoSizeIndex = 0
      Header.Height = 15
      Header.MainColumn = -1
      Header.Options = [hoDblClickResize, hoDrag, hoHotTrack]
      Indent = 20
      TabOrder = 0
      TreeOptions.PaintOptions = [toShowButtons, toShowDropmark, toShowRoot, toShowTreeLines, toThemeAware, toUseBlendedImages]
      TreeOptions.SelectionOptions = [toFullRowSelect]
      OnFreeNode = vstPreviewFreeNode
      OnGetCellText = vstPreviewGetCellText
      OnGetNodeDataSize = vstPreviewGetNodeDataSize
      Touch.InteractiveGestures = [igPan, igPressAndTap]
      Touch.InteractiveGestureOptions = [igoPanSingleFingerHorizontal, igoPanSingleFingerVertical, igoPanInertia, igoPanGutter, igoParentPassthrough]
      ExplicitLeft = 0
      ExplicitTop = 0
      ExplicitWidth = 647
      ExplicitHeight = 524
      Columns = <>
    end
  end
end
