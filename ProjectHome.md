**A TCP socket-based service layer on ClearQuest that enables platform-independent clients to execute ClearQuest commands via XML.**

### Overview ###
The ClearQuest XML Interface is a service layer on IBM's ClearQuest that allows platform-independent clients to send ClearQuest commands via XML. IBM's comparable solution required additional server hardware and installation of proprietary software on each client machine. Additionally, our implementation works better over the WAN, is scalable and utilizes a generic interface.

### Details ###
The ClearQuest XML Interface (CQ/XML) is a service that waits for incoming TCP socket connections. Upon a successful connection, CQ/XML reads the XML coming through the socket. If the XML is not well-formatted, CQ/XML sends an XML-formatted error back to the sender. If the XML is well-formatted, CQ/XML logs-in to ClearQuest as the connecting user. The parsed commands are then executed within ClearQuest as that user. The result from each command is saved, reformatted as XML and sent back through the socket to the client before closing the socket.

### Justification ###
The use of CQ/XML as a "ClearQuest layer" instead of a "database layer" gives us several advantages over the direct database access that some of our customers have asked for. For one, ClearQuest business rules are still enforced. Secondly, we can enforce ClearQuest logins and passwords. Most importantly, ClearQuest history is maintained without compromising the integrity of the database.

### Results ###
CQ/XML has been extremely stable, with no application-level failures encountered through seven months of testing and fifteen months of production deployment. It scales extremely well. Under Sun Grid Engine tests, CQ/XML was still handling requests with over 350 near-simultaneous connections. Our user community has created several amazing extensions to ClearQuest, including completely new web interfaces, GUI-enabled version control system integrations, RSS feeds, plus more. Time permitting, we'd love to clean them up and post them out here as well.