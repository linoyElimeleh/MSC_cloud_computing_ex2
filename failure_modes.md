# Failure Modes and Handling
## Overload
When my servers are swallowed with requests (e.g., during pick hours, bot attacks, etc.), the request queue can get too long, resulting in a slower response time. The two most common ways of handling this are to turn away requests when the server is too busy or handle each request slower.

## Software Failure
In this exercise, I wasn't required to deal with edge cases, therefore, my application might fail due to bad requests, wrong input, and many more reasons. If it was a production system, I'd have to research for edge cases and cover them. Moreover, I'd test my code before deployment and if possible, have a QA engineer test it.

## Hardware Failure
Hardware can be tricky, especially when using cloud providers, and can be defected for many reasons, such as abuse, mechanical defect, electronic defect, earthquakes, and many more. To overcome hardware failures, I need to have a backup for all the components in the cluster, including the database that is currently hosted locally and should be hosted and replicated on different machines. Moreover, I need to have a heartbeat that checks that all machines are working and, if necessary, fire a replacement.

## Network Failure
Network failures can happen for the same reasons as mentioned in the hardware section. Those failures can result in the loss of request, e.g.:
- Deleting a job from the queue before getting the request back.
- Uploading/downloading only part of the data.

I'd resolve those issues by keeping the requests and results in a database outside the cluster. However, if a request fails before hitting the end-point, I don't really have a lot to do.

## Security
Cyber Cyber Cyber I put in A LOT of work not to move the user's credentials to any of the machines. However, I'm sure my system has security breaches I'm not aware of. I'd definitely take a consultant in this case because it's too far away from my domain.
