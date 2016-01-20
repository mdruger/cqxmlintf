# Introduction #

**CQ/XML Interface - What's New - Release: 2008-10-13**


# Details #
```
cqext.pm
    - Query()
        - pass querydef obj to QueryOutput()
    - FixQueryCurUsr()
        - added CqSvr::PrnDbgHdr()
    - QueryOutput()
        - added CqSvr::PrnDbgHdr()
        - call GetColProps() to get column labels & types
        - if null multi-key ref-list, rm spaces
    - GetColProps()
        - NEW: get column properties for a query
    - RawSql()
        - convert spec chars to xml entities before building query

cqsvrfuncs.pm
    - MkDirTree()
        - test if full path is sent
    - Decrypt()
        - check if values passed for looking up in hash
    - Log2Xml()
        - check if attribute set before printing

cqsvrvars.pm
    - NEW: $ipqerrfile  (IPQ err log file)
    - NEW: $statusfile  (log maint status file)
    - NEW: $statusext   (log maint file extension)
    - NEW: $logtblhdr   (log maint table header regexp)
    - NEW: $logupdstr   (log maint update string)
    - NEW: $loglinestr  (log maint row regexp)
    - NEW: $chkfreq     (IPQ check frequency)
    - NEW: $chkwarn     (IPQ check frequency)
    - NEW: $noatrbstr   (string if attribute is missing)

cqxi_live.pl
    - main()
        - added SO_KEEPALIVE to socket
        - added SO_LINGER to socket
        - set client host to def val if unresolved
        - lengthened timeout on socket read

cqxi_queued.pl
    - main()
        - if errors from CqSys::FindSvrProcs(), try alt method before fail
        - force xml request to correct log
    - ProcessQueued()
        - take file date as arg and use to move logs to correct dir
    - ReadCmd()
        - use scoped vars
    - CloseQueueLog()
        - NEW: closes the queue log file
    - RecordLiveLog()
        - go thru files by date

cqxml.pm
    - CqExecXml()
        - check if <sql> command is in PCDATA or CDATA

support/cp2svr.sh
    - main()
        - added support/cqxi_logmaint.pl and support/prndbghdr.pm to $SUPPORT

support/cqtan_date.pl
    - main()
        - prn full date str w/ cqtan date

support/cqxi_chklive.pl
    - main()
        - require prndbghdr.pm instead of cqsvrfuncs.pm
        - call ChkIpq() if enabled
    - ParseCmd()
        - support different debug levels via '-d'
        - added '-i' to check ipq files
        - explicitly use scoped vars
    - ChkIpq()
        - NEW: checks if there is a backlog of ipq files
    - GenIpqErrList()
        - NEW: find ipq files that are too old or 0 size
    - ReadIpqErrLog()
        - NEW: read ipq err log
    - CompareIpqErrs()
        - NEW: compare known ipq errs w/ new ipq errs
    - WriteIpqErrLog()
        - NEW: writes ipq errors to file
    - RestartSvr()
        - changed message format

support/crontab.txt
    - NEW: once a day run cqxi_logmaint.pl
    - added '-i' switch to cqxi_chklive.pl cmd

support/cqxi_logmaint.pl
    - NEW
    - removes old output logs, checks status of current logs

support/prndbghdr.pm
    - NEW
    - prints debug header info

docs/admin/admin.html
    - changed "Monthly Stats" to "Stats"
    - NEW: link to maintenance logs

docs/admin/logs.html
    - added note about cqxi_logmaint.pl

docs/admin/overview.html
    - added note about cqxi_logmaint.pl
    - added note about prndbghdr.pm

docs/admin/setup.html
    - added directory option to secCXinst.sh call

docs/admin/stats.html
    - removed all the "monthly" headings
    - added daily usage stats

docs/user/common.html
    - added note about adding to version lists

docs/user/run_query.php.txt
    - PHP sample code
```