
.\SEND_ORDER_TREND.ps1 `
  -CsvPath "D:\Wagner\incomming\postenbestellung_81175_1763541893.csv" `
  -ApiBaseUrl "http://localhost:8085/api/ibmi/s105dd7a" `
  -BearerToken "IOwIAdKxAuBvlqzOgR9rr9wCmtX7SRaaxnfDjeVSd46c7b41" `
  -UserInterface "EASYIMPORT" `
  -ChannelId "00025" `
  -LogPath "D:\Wagner\order_import.log" `
  -RequestDumpDirectory "D:\Wagner\order_requests" `
  #-TestMode `
  #-DryRun

