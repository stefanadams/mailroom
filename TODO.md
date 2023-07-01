# TODO:

#   Connect to database
#   Set unix domain socket permission correctly
#   Log who it was originally to as well as the final to
#   Leverage Message-ID to respond from who it was originally to
#   Web interface to add domains and manage aliases

#   Use SRS to pass DMARC (https://www.unlocktheinbox.com/resources/srs/)
#     https://metacpan.org/pod/Mail::SRS
#     https://www.libsrs2.org/srs/srs.pdf
#   Multi-tenancy (minion admin ui, mainly)
#     Handle with queues (but how to grant very auth to various queue)
#   Command: add domain to sendgrid (requires sendgrid api)
#   Should each domain have its own sendgrid api?
#   Web: add, lookup, remove, add domain
#   Test failed jobs
#   X Any way to link jobs / logs here with logs in sendgrid activity?
#   Command: Authenticated SMTP for sending as
#   On Spam: enqueue it and fail it for digesting later
#   Test wildcard recipient
