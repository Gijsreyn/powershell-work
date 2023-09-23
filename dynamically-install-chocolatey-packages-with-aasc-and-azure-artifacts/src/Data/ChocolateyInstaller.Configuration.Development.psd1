$ConfigurationData =
@{
    AllNodes =
    @(
        @{
            NodeName           = '<nodeName>'
            Role               = '<role>'
            StandaloneSoftware = @('notepadplusplus.install')
            RemoteSoftware     = @(
                @{
                    Name       = 'sql-server-2019-cumulative-update'
                    Arguments  = '/UpdateFileLocation:C:\Users\Client\Temp\sql-server-2019-cumulative-update\15.0.4322.2\SQLServer2019-KB5027702-x64.exe /IgnorePendingReboot'
                    RemoteFile = 'sql-server-2019-cumulative-update/15.0.4322.2/SQLServer2019-KB5027702-x64.exe'
                }
            )
        }
        # Expand more nodes
    )
}
