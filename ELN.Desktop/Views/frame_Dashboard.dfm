object frameDashboard: TframeDashboard
  AlignWithMargins = True
  Left = 0
  Top = 0
  Width = 800
  Height = 600
  TabOrder = 0
  object Splitter2: TSplitter
    Left = 0
    Top = 61
    Width = 800
    Height = 4
    Cursor = crVSplit
    Align = alTop
    ExplicitTop = 340
  end
  object pnlWelcome: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 0
    Width = 794
    Height = 58
    Margins.Top = 0
    Align = alTop
    AutoSize = True
    BorderOuter = fsFlatRounded
    TabOrder = 0
    Transparent = True
    Color = clBtnFace
    DesignSize = (
      794
      58)
    object pbAvatar: TPaintBox
      AlignWithMargins = True
      Left = 12
      Top = 5
      Width = 48
      Height = 48
      Margins.Top = 5
      Margins.Bottom = 5
      OnPaint = pbAvatarPaint
    end
    object lblGreeting: TRzLabel
      Left = 72
      Top = 3
      Width = 72
      Height = 21
      Caption = 'Welcome'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -16
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
      Transparent = True
    end
    object lblRoleDate: TRzLabel
      Left = 72
      Top = 29
      Width = 23
      Height = 15
      Caption = 'Role'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGray
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object lblQuickStats: TRzLabel
      Left = 300
      Top = 19
      Width = 3
      Height = 15
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGray
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object lblScale: TRzLabel
      Left = 580
      Top = 21
      Width = 30
      Height = 15
      Alignment = taRightJustify
      Anchors = [akTop, akRight]
      Caption = 'Scale:'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGray
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object cbScale: TComboBox
      Left = 616
      Top = 17
      Width = 70
      Height = 23
      Style = csDropDownList
      Anchors = [akTop, akRight]
      TabOrder = 1
      OnChange = cbScaleChange
      Items.Strings = (
        '80%'
        '100%'
        '120%'
        '150%')
    end
    object btnRefresh: TRzBitBtn
      AlignWithMargins = True
      Left = 730
      Top = 7
      Width = 52
      Height = 44
      Hint = 'Refresh'
      Margins.Left = 10
      Margins.Top = 5
      Margins.Right = 10
      Margins.Bottom = 5
      ShowDownPattern = False
      ShowFocusRect = False
      Align = alRight
      ParentShowHint = False
      ShowHint = True
      TabOrder = 0
      OnClick = btnRefreshClick
      ImageIndex = 12
      Images = dmTreeImages.vilMenuImages
      Margin = -1
      Spacing = 0
      ExplicitLeft = 732
      ExplicitTop = 12
      ExplicitHeight = 34
    end
  end
  object pnlFilters: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 65
    Width = 794
    Height = 36
    Margins.Top = 0
    Align = alTop
    BorderOuter = fsFlatRounded
    TabOrder = 2
    Transparent = True
    Visible = False
    object lblFilterUser: TRzLabel
      Left = 12
      Top = 9
      Width = 28
      Height = 15
      Caption = 'User:'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGray
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object lblFilterTimeRange: TRzLabel
      Left = 248
      Top = 9
      Width = 68
      Height = 15
      Caption = 'Time Range:'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGray
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object cbFilterUser: TComboBox
      Left = 48
      Top = 6
      Width = 180
      Height = 23
      Style = csDropDownList
      TabOrder = 0
      OnChange = FilterChanged
    end
    object cbFilterTimeRange: TComboBox
      Left = 328
      Top = 6
      Width = 120
      Height = 23
      Style = csDropDownList
      TabOrder = 1
      OnChange = FilterChanged
      Items.Strings = (
        '1 Week'
        '1 Month'
        '3 Months'
        '6 Months'
        '1 Year'
        'All Time')
    end
  end
  object RzPanel1: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 104
    Width = 794
    Height = 493
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 1
    Color = clBtnFace
    object pnlBottom: TPanel
      AlignWithMargins = True
      Left = 5
      Top = 271
      Width = 784
      Height = 253
      Align = alClient
      BevelOuter = bvNone
      ParentBackground = False
      TabOrder = 0
      object Splitter3: TSplitter
        Left = 400
        Top = 0
        Width = 4
        Height = 253
        ExplicitHeight = 256
      end
      object pnlProjects: TPanel
        Left = 0
        Top = 0
        Width = 400
        Height = 253
        Align = alLeft
        BevelOuter = bvNone
        TabOrder = 0
        object pbHeaderProjects: TPaintBox
          AlignWithMargins = True
          Left = 15
          Top = 3
          Width = 382
          Height = 32
          Margins.Left = 15
          Align = alTop
          OnPaint = pbHeaderProjectsPaint
          ExplicitLeft = 0
          ExplicitTop = 0
          ExplicitWidth = 400
        end
        object lbProjects: TListBox
          Left = 0
          Top = 38
          Width = 400
          Height = 215
          Style = lbVirtualOwnerDraw
          Align = alClient
          BorderStyle = bsNone
          Color = clBtnFace
          ItemHeight = 48
          TabOrder = 0
          StyleElements = [seFont, seBorder]
          OnDrawItem = lbProjectsDrawItem
        end
      end
      object pnlActivity: TPanel
        Left = 404
        Top = 0
        Width = 380
        Height = 253
        Align = alClient
        BevelOuter = bvNone
        TabOrder = 1
        object pbHeaderActivity: TPaintBox
          AlignWithMargins = True
          Left = 15
          Top = 3
          Width = 362
          Height = 32
          Margins.Left = 15
          Align = alTop
          OnPaint = pbHeaderActivityPaint
          ExplicitLeft = 0
          ExplicitTop = 0
          ExplicitWidth = 396
        end
        object lbActivity: TListBox
          Left = 0
          Top = 38
          Width = 380
          Height = 215
          Style = lbVirtualOwnerDraw
          Align = alClient
          BorderStyle = bsNone
          Color = clBtnFace
          ItemHeight = 40
          TabOrder = 0
          StyleElements = [seFont, seBorder]
          OnClick = lbActivityClick
          OnDrawItem = lbActivityDrawItem
        end
      end
    end
    object pnlTop: TPanel
      AlignWithMargins = True
      Left = 5
      Top = 5
      Width = 784
      Height = 260
      Align = alTop
      BevelOuter = bvNone
      ParentBackground = False
      TabOrder = 1
      object Splitter1: TSplitter
        Left = 400
        Top = 0
        Width = 4
        Height = 260
      end
      object pnlRecentItems: TPanel
        Left = 0
        Top = 0
        Width = 400
        Height = 260
        Align = alLeft
        BevelOuter = bvNone
        TabOrder = 0
        object pbHeaderRecent: TPaintBox
          AlignWithMargins = True
          Left = 15
          Top = 3
          Width = 382
          Height = 32
          Margins.Left = 15
          Align = alTop
          OnPaint = pbHeaderRecentPaint
          ExplicitLeft = 0
          ExplicitTop = 0
          ExplicitWidth = 400
        end
        object lbRecentItems: TListBox
          Left = 0
          Top = 38
          Width = 400
          Height = 222
          Style = lbVirtualOwnerDraw
          Align = alClient
          BorderStyle = bsNone
          Color = clBtnFace
          ItemHeight = 52
          TabOrder = 0
          StyleElements = [seFont, seBorder]
          OnClick = lbRecentItemsClick
          OnDrawItem = lbRecentItemsDrawItem
        end
      end
      object pnlProtocols: TPanel
        Left = 404
        Top = 0
        Width = 380
        Height = 260
        Align = alClient
        BevelOuter = bvNone
        TabOrder = 1
        object pbHeaderProtocols: TPaintBox
          AlignWithMargins = True
          Left = 15
          Top = 3
          Width = 362
          Height = 32
          Margins.Left = 15
          Align = alTop
          OnPaint = pbHeaderProtocolsPaint
          ExplicitLeft = 0
          ExplicitTop = 0
          ExplicitWidth = 396
        end
        object lbProtocols: TListBox
          Left = 0
          Top = 38
          Width = 380
          Height = 222
          Style = lbVirtualOwnerDraw
          Align = alClient
          BorderStyle = bsNone
          Color = clBtnFace
          ItemHeight = 52
          TabOrder = 0
          StyleElements = [seFont, seBorder]
          OnClick = lbProtocolsClick
          OnDrawItem = lbProtocolsDrawItem
        end
      end
      object Splitter4: TSplitter
        Left = 784
        Top = 0
        Width = 4
        Height = 260
        Align = alRight
      end
      object pnlApprovals: TPanel
        Left = 788
        Top = 0
        Width = 360
        Height = 260
        Align = alRight
        BevelOuter = bvNone
        TabOrder = 2
        object pbHeaderApprovals: TPaintBox
          AlignWithMargins = True
          Left = 15
          Top = 3
          Width = 342
          Height = 32
          Margins.Left = 15
          Align = alTop
          OnPaint = pbHeaderApprovalsPaint
        end
        object lbApprovals: TListBox
          AlignWithMargins = True
          Left = 3
          Top = 41
          Width = 354
          Height = 216
          Style = lbVirtualOwnerDraw
          Align = alClient
          BorderStyle = bsNone
          Color = clBtnFace
          ItemHeight = 52
          TabOrder = 0
          StyleElements = [seFont, seBorder]
          OnClick = lbApprovalsClick
          OnDrawItem = lbApprovalsDrawItem
        end
      end
    end
  end
end
