/*
 $Id: Encode.xs,v 1.55 2003/02/28 01:40:27 dankogai Exp dankogai $
 */

#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#define U8 U8
#include "encode.h"

# define PERLIO_MODNAME  "PerlIO::encoding"
# define PERLIO_FILENAME "PerlIO/encoding.pm"

/* set 1 or more to profile.  t/encoding.t dumps core because of
   Perl_warner and PerlIO don't work well */
#define ENCODE_XS_PROFILE 0

/* set 0 to disable floating point to calculate buffer size for
   encode_method().  1 is recommended. 2 restores NI-S original */
#define ENCODE_XS_USEFP   1

#define UNIMPLEMENTED(x,y) y x (SV *sv, char *encoding) {dTHX;   \
                         Perl_croak(aTHX_ "panic_unimplemented"); \
			 return (y)0; /* fool picky compilers */ \
                         }
/**/

UNIMPLEMENTED(_encoded_utf8_to_bytes, I32)
UNIMPLEMENTED(_encoded_bytes_to_utf8, I32)

void
Encode_XSEncoding(pTHX_ encode_t * enc)
{
    dSP;
    HV *stash = gv_stashpv("Encode::XS", TRUE);
    SV *sv = sv_bless(newRV_noinc(newSViv(PTR2IV(enc))), stash);
    int i = 0;
    PUSHMARK(sp);
    XPUSHs(sv);
    while (enc->name[i]) {
	const char *name = enc->name[i++];
	XPUSHs(sv_2mortal(newSVpvn(name, strlen(name))));
    }
    PUTBACK;
    call_pv("Encode::define_encoding", G_DISCARD);
    SvREFCNT_dec(sv);
}

void
call_failure(SV * routine, U8 * done, U8 * dest, U8 * orig)
{
    /* Exists for breakpointing */
}


#define ERR_ENCODE_NOMAP "\"\\x{%04" UVxf "}\" does not map to %s"
#define ERR_DECODE_NOMAP "%s \"\\x%02" UVXf "\" does not map to Unicode"

static SV *
encode_method(pTHX_ encode_t * enc, encpage_t * dir, SV * src,
	      int check, STRLEN * offset, SV * term, int * retcode)
{
    STRLEN slen;
    U8 *s = (U8 *) SvPV(src, slen);
    STRLEN tlen  = slen;
    STRLEN ddone = 0;
    STRLEN sdone = 0;

    /* We allocate slen+1.
       PerlIO dumps core if this value is smaller than this. */
    SV *dst = sv_2mortal(newSV(slen+1));
    U8 *d = (U8 *)SvPVX(dst);
    STRLEN dlen = SvLEN(dst)-1;
    int code = 0;
    STRLEN trmlen = 0;
    U8 *trm = term ? (U8*) SvPV(term, trmlen) : NULL;

    if (offset) {
      s += *offset;
      if (slen > *offset){ /* safeguard against slen overflow */
	  slen -= *offset;
      }else{
	  slen = 0;
      }
      tlen = slen;
    }

    if (slen == 0){
	SvCUR_set(dst, 0);
	SvPOK_only(dst);
	goto ENCODE_END;
    }

    while( (code = do_encode(dir, s, &slen, d, dlen, &dlen, !check,
			     trm, trmlen)) ) 
    {
	SvCUR_set(dst, dlen+ddone);
	SvPOK_only(dst);
	
	if (code == ENCODE_FALLBACK || code == ENCODE_PARTIAL ||
	    code == ENCODE_FOUND_TERM) {
	    break;
	}
	switch (code) {
	case ENCODE_NOSPACE:
	{	
	    STRLEN more = 0; /* make sure you initialize! */
	    STRLEN sleft;
	    sdone += slen;
	    ddone += dlen;
	    sleft = tlen - sdone;
#if ENCODE_XS_PROFILE >= 2
	    Perl_warn(aTHX_
		      "more=%d, sdone=%d, sleft=%d, SvLEN(dst)=%d\n",
		      more, sdone, sleft, SvLEN(dst));
#endif
	    if (sdone != 0) { /* has src ever been processed ? */
#if   ENCODE_XS_USEFP == 2
		more = (1.0*tlen*SvLEN(dst)+sdone-1)/sdone
		    - SvLEN(dst);
#elif ENCODE_XS_USEFP
		more = (STRLEN)((1.0*SvLEN(dst)+1)/sdone * sleft);
#else
		/* safe until SvLEN(dst) == MAX_INT/16 */
		more = (16*SvLEN(dst)+1)/sdone/16 * sleft;
#endif
	    }
	    more += UTF8_MAXLEN; /* insurance policy */
	    d = (U8 *) SvGROW(dst, SvLEN(dst) + more);
	    /* dst need to grow need MORE bytes! */
	    if (ddone >= SvLEN(dst)) {
		Perl_croak(aTHX_ "Destination couldn't be grown.");
	    }
	    dlen = SvLEN(dst)-ddone-1;
	    d   += ddone;
	    s   += slen;
	    slen = tlen-sdone;
	    continue;
	}
	case ENCODE_NOREP:
	    /* encoding */	
	    if (dir == enc->f_utf8) {
		STRLEN clen;
		UV ch =
		    utf8n_to_uvuni(s+slen, (SvCUR(src)-slen),
				   &clen, UTF8_ALLOW_ANY|UTF8_CHECK_ONLY);
		if (check & ENCODE_DIE_ON_ERR) {
		    Perl_croak(aTHX_ ERR_ENCODE_NOMAP,
			       (UV)ch, enc->name[0]);
		    return &PL_sv_undef; /* never reaches but be safe */
		}
		if (check & ENCODE_WARN_ON_ERR){
		    Perl_warner(aTHX_ packWARN(WARN_UTF8),
				ERR_ENCODE_NOMAP, (UV)ch, enc->name[0]);
		}
		if (check & ENCODE_RETURN_ON_ERR){
		    goto ENCODE_SET_SRC;
		}
		if (check & ENCODE_PERLQQ){
		    SV* perlqq = 
			sv_2mortal(newSVpvf("\\x{%04"UVxf"}", (UV)ch));
		    sdone += slen + clen;
		    ddone += dlen + SvCUR(perlqq);
		    sv_catsv(dst, perlqq);
		}else if (check & ENCODE_HTMLCREF){
		    SV* htmlcref = 
			sv_2mortal(newSVpvf("&#%" UVuf ";", (UV)ch));
		    sdone += slen + clen;
		    ddone += dlen + SvCUR(htmlcref);
		    sv_catsv(dst, htmlcref);
		}else if (check & ENCODE_XMLCREF){
		    SV* xmlcref = 
			sv_2mortal(newSVpvf("&#x%" UVxf ";", (UV)ch));
		    sdone += slen + clen;
		    ddone += dlen + SvCUR(xmlcref);
		    sv_catsv(dst, xmlcref);
		} else {
		    /* fallback char */
		    sdone += slen + clen;
		    ddone += dlen + enc->replen;
		    sv_catpvn(dst, (char*)enc->rep, enc->replen);
		}
	    }
	    /* decoding */
	    else {
		if (check & ENCODE_DIE_ON_ERR){
		    Perl_croak(aTHX_ ERR_DECODE_NOMAP,
                              enc->name[0], (UV)s[slen]);
		    return &PL_sv_undef; /* never reaches but be safe */
		}
		if (check & ENCODE_WARN_ON_ERR){
		    Perl_warner(
			aTHX_ packWARN(WARN_UTF8),
			ERR_DECODE_NOMAP,
               	        enc->name[0], (UV)s[slen]);
		}
		if (check & ENCODE_RETURN_ON_ERR){
		    goto ENCODE_SET_SRC;
		}
		if (check &
		    (ENCODE_PERLQQ|ENCODE_HTMLCREF|ENCODE_XMLCREF)){
		    SV* perlqq = 
			sv_2mortal(newSVpvf("\\x%02" UVXf, (UV)s[slen]));
		    sdone += slen + 1;
		    ddone += dlen + SvCUR(perlqq);
		    sv_catsv(dst, perlqq);
		} else {
		    sdone += slen + 1;
		    ddone += dlen + strlen(FBCHAR_UTF8);
		    sv_catpv(dst, FBCHAR_UTF8);
		}
	    }
	    /* settle variables when fallback */
	    d    = (U8 *)SvEND(dst);
            dlen = SvLEN(dst) - ddone - 1;
	    s    = (U8*)SvPVX(src) + sdone;
	    slen = tlen - sdone;
	    break;

	default:
	    Perl_croak(aTHX_ "Unexpected code %d converting %s %s",
		       code, (dir == enc->f_utf8) ? "to" : "from",
		       enc->name[0]);
	    return &PL_sv_undef;
	}
    }
 ENCODE_SET_SRC:
    if (check && !(check & ENCODE_LEAVE_SRC)){
	sdone = SvCUR(src) - (slen+sdone);
	if (sdone) {
	    sv_setpvn(src, (char*)s+slen, sdone);
	}
	SvCUR_set(src, sdone);
    }
    /* warn("check = 0x%X, code = 0x%d\n", check, code); */

    SvCUR_set(dst, dlen+ddone);
    SvPOK_only(dst);

#if ENCODE_XS_PROFILE
    if (SvCUR(dst) > SvCUR(src)){
	Perl_warn(aTHX_
		  "SvLEN(dst)=%d, SvCUR(dst)=%d. %d bytes unused(%f %%)\n",
		  SvLEN(dst), SvCUR(dst), SvLEN(dst) - SvCUR(dst),
		  (SvLEN(dst) - SvCUR(dst))*1.0/SvLEN(dst)*100.0);
    }
#endif

    if (offset) 
      *offset += sdone + slen;

 ENCODE_END:
    *SvEND(dst) = '\0';
    if (retcode) *retcode = code;
    return dst;
}

MODULE = Encode		PACKAGE = Encode::utf8	PREFIX = Method_

void
Method_decode_xs(obj,src,check = 0)
SV *	obj
SV *	src
int	check
CODE:
{
    STRLEN slen;
    U8 *s = (U8 *) SvPV(src, slen);
    U8 *e = (U8 *) SvEND(src);
    SV *dst = newSV(slen>0?slen:1); /* newSV() abhors 0 -- inaba */
    SvPOK_only(dst);
    SvCUR_set(dst,0);
    if (SvUTF8(src)) {
	s = utf8_to_bytes(s,&slen);
	if (s) {
	    SvCUR_set(src,slen);
	    SvUTF8_off(src);
	    e = s+slen;
	}
	else {
	    croak("Cannot decode string with wide characters");
	}
    }
    while (s < e) {
    	if (UTF8_IS_INVARIANT(*s) || UTF8_IS_START(*s)) {
	    U8 skip = UTF8SKIP(s);
	    if ((s + skip) > e) {
	    	/* Partial character - done */
	    	break;
	    }
	    else if (is_utf8_char(s)) {
	    	/* Whole char is good */
		sv_catpvn(dst,(char *)s,skip);
		s += skip;
		continue;
	    }
	    else {
	    	/* starts ok but isn't "good" */
	    }
	}
	else {
	    /* Invalid start byte */
	}
	/* If we get here there is something wrong with alleged UTF-8 */
	if (check & ENCODE_DIE_ON_ERR){
	    Perl_croak(aTHX_ ERR_DECODE_NOMAP, "utf8", (UV)*s);
	    XSRETURN(0);
	}
	if (check & ENCODE_WARN_ON_ERR){
	    Perl_warner(aTHX_ packWARN(WARN_UTF8),
			ERR_DECODE_NOMAP, "utf8", (UV)*s);
        }
    	if (check & ENCODE_RETURN_ON_ERR) {
		break;
    	}
        if (check & (ENCODE_PERLQQ|ENCODE_HTMLCREF|ENCODE_XMLCREF)){
	    SV* perlqq = newSVpvf("\\x%02" UVXf, (UV)*s);
    	    sv_catsv(dst, perlqq);
	    SvREFCNT_dec(perlqq);
	} else {
	    sv_catpv(dst, FBCHAR_UTF8);
	}
	s++;
    }
    *SvEND(dst) = '\0';

    /* Clear out translated part of source unless asked not to */
    if (check && !(check & ENCODE_LEAVE_SRC)){
	slen = e-s;
	if (slen) {
	    sv_setpvn(src, (char*)s, slen);
	}
	SvCUR_set(src, slen);
    }
    SvUTF8_on(dst);
    ST(0) = sv_2mortal(dst);
    XSRETURN(1);
}

void
Method_encode_xs(obj,src,check = 0)
SV *	obj
SV *	src
int	check
CODE:
{
    STRLEN slen;
    U8 *s = (U8 *) SvPV(src, slen);
    U8 *e = (U8 *) SvEND(src);
    SV *dst = newSV(slen>0?slen:1); /* newSV() abhors 0 -- inaba */
    if (SvUTF8(src)) {
        /* Already encoded - trust it and just copy the octets */
    	sv_setpvn(dst,(char *)s,(e-s));
	s = e;
    }
    else {
    	/* Native bytes - can always encode */
	U8 *d = (U8 *) SvGROW(dst, 2*slen+1); /* +1 or assertion will botch */
    	while (s < e) {
    	    UV uv = NATIVE_TO_UNI((UV) *s++);
            if (UNI_IS_INVARIANT(uv))
            	*d++ = (U8)UTF_TO_NATIVE(uv);
            else {
    	        *d++ = (U8)UTF8_EIGHT_BIT_HI(uv);
                *d++ = (U8)UTF8_EIGHT_BIT_LO(uv);
            }
	}
        SvCUR_set(dst, d- (U8 *)SvPVX(dst));
    	*SvEND(dst) = '\0';
    }

    /* Clear out translated part of source unless asked not to */
    if (check && !(check & ENCODE_LEAVE_SRC)){
	slen = e-s;
	if (slen) {
	    sv_setpvn(src, (char*)s, slen);
	}
	SvCUR_set(src, slen);
    }
    SvPOK_only(dst);
    SvUTF8_off(dst);
    ST(0) = sv_2mortal(dst);
    XSRETURN(1);
}

MODULE = Encode		PACKAGE = Encode::XS	PREFIX = Method_

PROTOTYPES: ENABLE

void
Method_name(obj)
SV *	obj
CODE:
{
    encode_t *enc = INT2PTR(encode_t *, SvIV(SvRV(obj)));
    ST(0) = sv_2mortal(newSVpvn(enc->name[0],strlen(enc->name[0])));
    XSRETURN(1);
}

void
Method_cat_decode(obj, dst, src, off, term, check = 0)
SV *	obj
SV *	dst
SV *	src
SV *	off
SV *	term
int	check
CODE:
{
    encode_t *enc = INT2PTR(encode_t *, SvIV(SvRV(obj)));
    STRLEN offset = (STRLEN)SvIV(off);
    int code = 0;
    if (SvUTF8(src)) {
    	sv_utf8_downgrade(src, FALSE);
    }
    sv_catsv(dst, encode_method(aTHX_ enc, enc->t_utf8, src, check,
				&offset, term, &code));
    SvIVX(off) = (IV)offset;
    if (code == ENCODE_FOUND_TERM) {
	ST(0) = &PL_sv_yes;
    }else{
	ST(0) = &PL_sv_no;
    }
    XSRETURN(1);
}

void
Method_decode(obj,src,check = 0)
SV *	obj
SV *	src
int	check
CODE:
{
    encode_t *enc = INT2PTR(encode_t *, SvIV(SvRV(obj)));
    if (SvUTF8(src)) {
    	sv_utf8_downgrade(src, FALSE);
    }
    ST(0) = encode_method(aTHX_ enc, enc->t_utf8, src, check,
			  NULL, Nullsv, NULL);
    SvUTF8_on(ST(0));
    XSRETURN(1);
}

void
Method_encode(obj,src,check = 0)
SV *	obj
SV *	src
int	check
CODE:
{
    encode_t *enc = INT2PTR(encode_t *, SvIV(SvRV(obj)));
    sv_utf8_upgrade(src);
    ST(0) = encode_method(aTHX_ enc, enc->f_utf8, src, check,
			  NULL, Nullsv, NULL);
    XSRETURN(1);
}

void
Method_needs_lines(obj)
SV *	obj
CODE:
{
    /* encode_t *enc = INT2PTR(encode_t *, SvIV(SvRV(obj))); */
    ST(0) = &PL_sv_no;
    XSRETURN(1);
}

void
Method_perlio_ok(obj)
SV *	obj
CODE:
{
    /* encode_t *enc = INT2PTR(encode_t *, SvIV(SvRV(obj))); */
    /* require_pv(PERLIO_FILENAME); */

    eval_pv("require PerlIO::encoding", 0);

    if (SvTRUE(get_sv("@", 0))) {
	ST(0) = &PL_sv_no;
    }else{
	ST(0) = &PL_sv_yes;
    }
    XSRETURN(1);
}

MODULE = Encode         PACKAGE = Encode

PROTOTYPES: ENABLE

I32
_bytes_to_utf8(sv, ...)
SV *    sv
CODE:
{
    SV * encoding = items == 2 ? ST(1) : Nullsv;

    if (encoding)
    RETVAL = _encoded_bytes_to_utf8(sv, SvPV_nolen(encoding));
    else {
	STRLEN len;
	U8*    s = (U8*)SvPV(sv, len);
	U8*    converted;

	converted = bytes_to_utf8(s, &len); /* This allocs */
	sv_setpvn(sv, (char *)converted, len);
	SvUTF8_on(sv); /* XXX Should we? */
	Safefree(converted);                /* ... so free it */
	RETVAL = len;
    }
}
OUTPUT:
    RETVAL

I32
_utf8_to_bytes(sv, ...)
SV *    sv
CODE:
{
    SV * to    = items > 1 ? ST(1) : Nullsv;
    SV * check = items > 2 ? ST(2) : Nullsv;

    if (to) {
	RETVAL = _encoded_utf8_to_bytes(sv, SvPV_nolen(to));
    } else {
	STRLEN len;
	U8 *s = (U8*)SvPV(sv, len);

	RETVAL = 0;
	if (SvTRUE(check)) {
	    /* Must do things the slow way */
	    U8 *dest;
            /* We need a copy to pass to check() */
	    U8 *src  = (U8*)savepv((char *)s);
	    U8 *send = s + len;

	    New(83, dest, len, U8); /* I think */

	    while (s < send) {
                if (*s < 0x80){
		    *dest++ = *s++;
                } else {
		    STRLEN ulen;
		    UV uv = *s++;

		    /* Have to do it all ourselves because of error routine,
		       aargh. */
		    if (!(uv & 0x40)){ goto failure; }
		    if      (!(uv & 0x20)) { ulen = 2;  uv &= 0x1f; }
		    else if (!(uv & 0x10)) { ulen = 3;  uv &= 0x0f; }
		    else if (!(uv & 0x08)) { ulen = 4;  uv &= 0x07; }
		    else if (!(uv & 0x04)) { ulen = 5;  uv &= 0x03; }
		    else if (!(uv & 0x02)) { ulen = 6;  uv &= 0x01; }
		    else if (!(uv & 0x01)) { ulen = 7;  uv = 0; }
		    else                   { ulen = 13; uv = 0; }
		
		    /* Note change to utf8.c variable naming, for variety */
		    while (ulen--) {
			if ((*s & 0xc0) != 0x80){
			    goto failure;
			} else {
			    uv = (uv << 6) | (*s++ & 0x3f);
			}
		  }
		  if (uv > 256) {
		  failure:
		      call_failure(check, s, dest, src);
		      /* Now what happens? */
		  }
		  *dest++ = (U8)uv;
		}
	    }
	} else {
	    RETVAL = (utf8_to_bytes(s, &len) ? len : 0);
	}
    }
}
OUTPUT:
    RETVAL

bool
is_utf8(sv, check = 0)
SV *	sv
int	check
CODE:
{
    if (SvGMAGICAL(sv)) /* it could be $1, for example */
	sv = newSVsv(sv); /* GMAGIG will be done */
    if (SvPOK(sv)) {
	RETVAL = SvUTF8(sv) ? TRUE : FALSE;
	if (RETVAL &&
	    check  &&
	    !is_utf8_string((U8*)SvPVX(sv), SvCUR(sv)))
	    RETVAL = FALSE;
    } else {
	RETVAL = FALSE;
    }
    if (sv != ST(0))
	SvREFCNT_dec(sv); /* it was a temp copy */
}
OUTPUT:
    RETVAL

SV *
_utf8_on(sv)
SV *	sv
CODE:
{
    if (SvPOK(sv)) {
	SV *rsv = newSViv(SvUTF8(sv));
	RETVAL = rsv;
	SvUTF8_on(sv);
    } else {
	RETVAL = &PL_sv_undef;
    }
}
OUTPUT:
    RETVAL

SV *
_utf8_off(sv)
SV *	sv
CODE:
{
    if (SvPOK(sv)) {
	SV *rsv = newSViv(SvUTF8(sv));
	RETVAL = rsv;
	SvUTF8_off(sv);
    } else {
	RETVAL = &PL_sv_undef;
    }
}
OUTPUT:
    RETVAL

int
DIE_ON_ERR()
CODE:
    RETVAL = ENCODE_DIE_ON_ERR;
OUTPUT:
    RETVAL

int
WARN_ON_ERR()
CODE:
    RETVAL = ENCODE_WARN_ON_ERR;
OUTPUT:
    RETVAL

int
LEAVE_SRC()
CODE:
    RETVAL = ENCODE_LEAVE_SRC;
OUTPUT:
    RETVAL

int
RETURN_ON_ERR()
CODE:
    RETVAL = ENCODE_RETURN_ON_ERR;
OUTPUT:
    RETVAL

int
PERLQQ()
CODE:
    RETVAL = ENCODE_PERLQQ;
OUTPUT:
    RETVAL

int
HTMLCREF()
CODE:
    RETVAL = ENCODE_HTMLCREF;
OUTPUT:
    RETVAL

int
XMLCREF()
CODE:
    RETVAL = ENCODE_XMLCREF;
OUTPUT:
    RETVAL

int
FB_DEFAULT()
CODE:
    RETVAL = ENCODE_FB_DEFAULT;
OUTPUT:
    RETVAL

int
FB_CROAK()
CODE:
    RETVAL = ENCODE_FB_CROAK;
OUTPUT:
    RETVAL

int
FB_QUIET()
CODE:
    RETVAL = ENCODE_FB_QUIET;
OUTPUT:
    RETVAL

int
FB_WARN()
CODE:
    RETVAL = ENCODE_FB_WARN;
OUTPUT:
    RETVAL

int
FB_PERLQQ()
CODE:
    RETVAL = ENCODE_FB_PERLQQ;
OUTPUT:
    RETVAL

int
FB_HTMLCREF()
CODE:
    RETVAL = ENCODE_FB_HTMLCREF;
OUTPUT:
    RETVAL

int
FB_XMLCREF()
CODE:
    RETVAL = ENCODE_FB_XMLCREF;
OUTPUT:
    RETVAL

BOOT:
{
#include "def_t.h"
#include "def_t.exh"
}
