struct qr {
    unsigned q;        /* computed quotient */
    unsigned r;        /* computed remainder */
    unsigned q_n;        /* specficies if quotient shall be negative */
    unsigned r_n;        /* specficies if remainder shall be negative */
};

static void division_qr(unsigned n, unsigned p, struct qr *qr)
{
    unsigned i = 1, q = 0;
    if (p == 0) {
        qr->r = 0xFFFFFFFF;    /* division by 0 */
        return;
    }
    
    while ((p >> 31) == 0) {
        i = i << 1;    /* count the max division steps */
        p = p << 1;     /* increase p until it has maximum size*/
    }
    
    while (i > 0) {
        q = q << 1;    /* write bit in q at index (size-1) */
        if (n >= p)
        {
            n -= p;
            q++;
        }
        p = p >> 1;     /* decrease p */
        i = i >> 1;     /* decrease remaining size in q */
    }
    qr->r = n;
    qr->q = q;
}

static void uint_div_qr(unsigned numerator, unsigned denominator, struct qr *qr)
{
    
    division_qr(numerator, denominator, qr);
    
    /* negate quotient and/or remainder according to requester */
    if (qr->q_n)
    qr->q = -qr->q;
    if (qr->r_n)
    qr->r = -qr->r;
}

unsigned __aeabi_uidiv(unsigned numerator, unsigned denominator)
{
    struct qr qr;
    qr.q = 0;
    qr.r = 0;
    qr.q_n = 0;
    qr.r_n = 0;
    
    uint_div_qr(numerator, denominator, &qr);
    
    return qr.q;
}
