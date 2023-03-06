polySortV3
==========

  
My third attempt at creating a ideally working sorting system, using only the built-in `inventory` peripheral and wired modems.

  
In this iteration, there should be a host computer that manages both the sorting and indexing subroutines, sending out a rednet message containing the indexed itemTable for use by the client machines per their request. These client machines recieve the signal, update their itemTables, then use those to supply `list` and `request` functionality to the end user.

Installation instructions:
--------------------------

- Set up the host computer:

1. Connect to a bunch of chests via a wired modem.   
     Remember the names of one chest for input, and one chest for output.
2. Connect to a wireless modem.
3. OPTIONAL: connect to a monitor.
 
7. Use the pastebin code provided to download the host program to your host computer using `pastebin get  host`
8. Run the program on the computer. It'll freak out at you and create a config file. Edit it with `edit .settings.polySorter` The config file should explain what each config does, and that changing the input and output chests are required while changing the protocol is highly encouraged. Once you're done, save the file and run the program again. It should start working. If not, post an issue.
9. Next, Set up a client computer: any computer connected to a wireless modem.
10. Use the pastebin code provided to download the client to your computer using `pastebin get  client`
11. Change the protocol to whatever you set it as in the host config using `set host_protocol `
12. Run the client. You should be able to command your sorting system.
If you're wondering why my readme is in HTML, it's because I hate find it easier than markdown. I have no idea how to get gitHub to render it but I'll just pretend like it's working for now.