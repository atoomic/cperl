
/*
 * Copyright � 2001 Novell, Inc. All Rights Reserved.
 *
 * You may distribute under the terms of either the GNU General Public
 * License or the Artistic License, as specified in the README file.
 *
 */

/*
 * FILENAME		:	nw5sck.c
 * DESCRIPTION	:	Socket related functions.
 * Author		:	SGP
 * Date			:	January 2001.
 *
 */



#include "EXTERN.h"
#include "perl.h"

#if defined(PERL_OBJECT)
#define NO_XSLOCKS
#include "XSUB.h"
#endif

#include "nw5iop.h"
#include "nw5sck.h"
#include <fcntl.h>
#include <sys/stat.h>

static struct servent* nw_savecopyservent(struct servent*d,
                                             struct servent*s,
                                             const char *proto);


u_long
nw_htonl(u_long hostlong)
{
    return htonl(hostlong);
}

u_short
nw_htons(u_short hostshort)
{
    return htons(hostshort);
}

u_long
nw_ntohl(u_long netlong)
{
    return ntohl(netlong);
}

u_short
nw_ntohs(u_short netshort)
{
    return ntohs(netshort);
}

SOCKET
nw_accept(SOCKET s, struct sockaddr *addr, int *addrlen)
{
	return ((SOCKET)(accept(s, addr, addrlen)));
}

int
nw_bind(SOCKET s, const struct sockaddr *addr, int addrlen)
{
	return ((int)bind(s, (struct sockaddr *)addr, addrlen));

}

int
nw_connect(SOCKET s, const struct sockaddr *addr, int addrlen)
{
	return((int)connect(s, (struct sockaddr *)addr, addrlen));
}

void
nw_endhostent() 
{
	endhostent();
}

void
nw_endnetent()
{
	endnetent();
}

void
nw_endprotoent()
{
	endprotoent();
}

void
nw_endservent()
{
	endservent();
}

struct hostent *
nw_gethostent()
{
	return(gethostent());
}

struct netent *
nw_getnetent(void) 
{
    return ((struct netent *) getnetent());
}

struct protoent *
nw_getprotoent(void) 
{
    return ((struct protoent *) getprotoent());
}

struct hostent *
nw_gethostbyname(const char *name)
{
	return(gethostbyname((char*)name));
}

int
nw_gethostname(char *name, int len)
{
    return(gethostname(name, len));
}

struct hostent *
nw_gethostbyaddr(const char *addr, int len, int type)
{
	return(gethostbyaddr((char*)addr, len, type));
}

struct netent *
nw_getnetbyaddr(long net, int type) 
{
	return(getnetbyaddr(net,type));
}

struct netent *
nw_getnetbyname(char *name) 
{
    return (struct netent *)getnetbyname(name);
}

int
nw_getpeername(SOCKET s, struct sockaddr *addr, int *addrlen)
{
	return((int)getpeername(s, addr, addrlen));
}

struct protoent *
nw_getprotobyname(const char *name)
{
	return ((struct protoent *)getprotobyname((char*)name));
}

struct protoent *
nw_getprotobynumber(int num)
{
	return ((struct protoent *)getprotobynumber(num));
}

struct servent *
nw_getservbyname(const char *name, const char *proto)
{
	dTHXo; 
    struct servent *r;

    r = getservbyname((char*)name, (char*)proto);
    if (r) {
		/*r = nw_savecopyservent(&nw_servent, r, proto);*/
    }
    return r;
}


struct servent *
nw_getservbyport(int port, const char *proto)
{
    dTHXo; 
    struct servent *r;

    r = getservbyport(port, (char*)proto);
    if (r) {
		//r = nw_savecopyservent(&nw_servent, r, proto);
    }
    return r;
}

struct servent *
nw_getservent(void) 
{
    return (struct servent *) getservent();
}

void
nw_sethostent(int stayopen)
{
	sethostent(stayopen);
}

void
nw_setnetent(int stayopen)
{
	setnetent(stayopen);
}

void
nw_setprotoent(int stayopen)
{
	setprotoent(stayopen);
}

void
nw_setservent(int stayopen)
{
	setservent(stayopen);
}

int
nw_getsockname(SOCKET s, struct sockaddr *addr, int *addrlen)
{
	return getsockname(s, addr, addrlen);
}

int
nw_getsockopt(SOCKET s, int level, int optname, char *optval, int *optlen)
{
	return ((int)getsockopt(s, level, optname, optval, optlen));
}

unsigned long
nw_inet_addr(const char *cp)
{
    return inet_addr((char*)cp);
}

static struct servent*
nw_savecopyservent(struct servent*d, struct servent*s, const char *proto)
{
    d->s_name = s->s_name;
    d->s_aliases = s->s_aliases;
    d->s_port = s->s_port;
#ifndef __BORLANDC__	/* Buggy on Win95 and WinNT-with-Borland-WSOCK */
    if (/*!IsWin95() && */s->s_proto && strlen(s->s_proto))
	d->s_proto = s->s_proto;
    else
#endif
    if (proto && strlen(proto))
	d->s_proto = (char *)proto;
    else
	d->s_proto = "tcp";
   
    return d;
}

SOCKET
nw_socket(int af, int type, int protocol)
{
    SOCKET s;

#ifndef USE_SOCKETS_AS_HANDLES
    s = socket(af, type, protocol);
#else
    //StartSockets();
    if((s = socket(af, type, protocol)) == INVALID_SOCKET)
	//errno = WSAGetLastError();
    else
	s = s;
#endif	/* USE_SOCKETS_AS_HANDLES */

    return s;
}

int
nw_listen(SOCKET s, int backlog)
{
    return(listen(s, backlog));
}

int
nw_send(SOCKET s, const char *buf, int len, int flags)
{
	return(send(s,(char*)buf,len,flags));
}

int
nw_recv(SOCKET s, char *buf, int len, int flags)
{
	return (recv(s, buf, len, flags));
}

int
nw_sendto(SOCKET s, const char *buf, int len, int flags,
	     const struct sockaddr *to, int tolen)
{
    return(sendto(s, (char*)buf, len, flags, (struct sockaddr *)to, tolen));
}

int
nw_recvfrom(SOCKET s, char *buf, int len, int flags, struct sockaddr *from, int *fromlen)
{
    int r;
    int frombufsize = *fromlen;

    r = recvfrom(s, buf, len, flags, from, fromlen);
	//Not sure if the is required - chksgp
    if (r && frombufsize == *fromlen)
	(void)nw_getpeername(s, from, fromlen);
    return r;
}

int
nw_select(int nfds, fd_set* rd, fd_set* wr, fd_set* ex, const struct timeval* timeout)
{
	return(select(nfds, rd, wr, ex, (struct timeval*)timeout));
}

int
nw_shutdown(SOCKET s, int how)
{
    return (shutdown(s, how));
}

