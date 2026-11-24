/*
 * BDC: BASIC-DOS C Compiler
 *
 * @author Jeff Parsons
 * @copyright (c) 2026 Jeff Parsons
 * @license MIT <https://basicdos.com/LICENSE.txt>
 *
 * This file is part of PCjs, a computer emulation software project at pcjs.org
 *
 * Expressions.  Each expression becomes a tree of nodes, with its types and
 * conversions worked out, pointer arithmetic scaled, and constants folded,
 * and gen.c produces code from the tree.
 *
 * A variable is an N_DEREF of its address (N_ADDRG or N_ADDRL), so an lvalue
 * is simply an N_DEREF node, a member's address is its struct's address plus
 * a constant, and an array's value is its N_DEREF's operand.  A char's value
 * is always extended to an int, so an operation on chars has the type int.
 */

#include "bdc.h"

struct node nodes[NNODE];
int nodetop = 1;
int havepend;                   /* a name was read ahead of the */
int pendsym;                    /* expression that starts with it */
char pendname[NAMELEN];
int ininit;                     /* nonzero in an initializer */

static int unary();
static int cond();
static int binop();

#define KIND(t)     (types[t].kind)
#define ISPTR(t)    (KIND(t) == K_PTR)
#define ISLONG(t)   (KIND(t) == K_TLONG || KIND(t) == K_ULONG)
#define ISARITH(t)  (KIND(t) >= K_TCHAR && KIND(t) <= K_ULONG)
#define ISUNS(t)    (KIND(t) == K_UINT || KIND(t) == K_ULONG || ISPTR(t))

int mk(op, type, l, r)
int op, type, l, r;
{
    struct node *n;

    if (nodetop >= NNODE) fatal("expression too complex", "");
    STAT(8, nodetop + 1);
    n = &nodes[nodetop];
    n->op = op;
    n->type = type;
    n->left = l;
    n->right = r;
    n->sym = 0;
    n->val = 0;
    return nodetop++;
}

int konst(v, t)
long v;
int t;
{
    int n;

    n = mk(N_CONST, t, 0, 0);
    nodes[n].val = v;
    return n;
}

static int copyn(n, t)
int n, t;
{
    int m;

    m = mk(nodes[n].op, t, nodes[n].left, nodes[n].right);
    nodes[m].sym = nodes[n].sym;
    nodes[m].val = nodes[n].val;
    return m;
}

/*
 * Returns a value as a constant of the given type has it.
 */
long norm(v, t)
long v;
int t;
{
    switch (KIND(t)) {
    case K_TCHAR:
        v &= 0xFF;
        if (v & 0x80) v -= 0x100;
        break;
    case K_UCHAR:
        v &= 0xFF;
        break;
    case K_TINT:
        v &= 0xFFFFL;
        if (v & 0x8000L) v -= 0x10000L;
        break;
    case K_UINT:
    case K_PTR:
        v &= 0xFFFFL;
        break;
    case K_TLONG:
        v &= 0xFFFFFFFFL;
        if (v & 0x80000000L) {
            v -= 0x40000000L;
            v -= 0x40000000L;
            v -= 0x40000000L;
            v -= 0x40000000L;
        }
        break;
    case K_ULONG:
        v &= 0xFFFFFFFFL;
        break;
    }
    return v;
}

/*
 * Converts an array to a pointer to its first element, and a function to a
 * pointer to it.
 */
int rvalue(n)
int n;
{
    int t, c;

    t = nodes[n].type;
    if (KIND(t) == K_ARRAY && nodes[n].op == N_DEREF) {
        c = nodes[n].left;
        return copyn(c, ptrto(types[t].base));
    }
    if (KIND(t) == K_FUNC && nodes[n].op == N_ADDRG) {
        return copyn(n, ptrto(t));
    }
    return n;
}

int cast(n, t)
int n, t;
{
    int ft;

    ft = nodes[n].type;
    if (ft == t) return n;
    if (KIND(t) == K_STR || KIND(ft) == K_STR) {
        error("type mismatch", "");
        return n;
    }
    if (KIND(t) == K_FLT || KIND(ft) == K_FLT) {
        error("floating point isn't supported", "");
        return n;
    }
    if (KIND(t) == K_TVOID) return mk(N_CAST, t, n, 0);
    if (KIND(ft) == K_TVOID) {
        error("void value used", "");
        return n;
    }
    if (nodes[n].op == N_CONST) return konst(norm(nodes[n].val, t), t);
    if ((nodes[n].op == N_ADDRG || nodes[n].op == N_ADDRL) && tsize(t) == 2) {
        return copyn(n, t);
    }
    return mk(N_CAST, t, n, 0);
}

static unsigned elsize(t)
int t;
{
    unsigned n;

    n = tsize(types[t].base);
    return n ? n : 1;
}

/*
 * Adds constant or variable c to n, where the result has type t (16 bits).
 */
static int addnode(n, c, t)
int n, c, t;
{
    long v;
    int m;

    if (nodes[c].op != N_CONST) return mk(N_ADD, t, n, c);
    v = nodes[c].val;
    if (nodes[n].op == N_ADDRG || nodes[n].op == N_ADDRL) {
        m = copyn(n, t);
        nodes[m].val = norm(nodes[m].val + v, T_INT);
        return m;
    }
    if (nodes[n].op == N_CONST) return konst(norm(nodes[n].val + v, t), t);
    if (!v) return nodes[n].type == t ? n : cast(n, t);
    if (nodes[n].op == N_ADD && nodes[nodes[n].right].op == N_CONST) {
        v = norm(v + nodes[nodes[n].right].val, T_INT);
        return mk(N_ADD, t, nodes[n].left, konst(v, T_INT));
    }
    return mk(N_ADD, t, n, konst(norm(v, T_INT), T_INT));
}

static int scale(n, sz)
int n;
unsigned sz;
{
    if (sz == 1) return n;
    if (nodes[n].op == N_CONST) {
        return konst(norm(nodes[n].val * sz, T_INT), T_INT);
    }
    return mk(N_MUL, T_INT, n, konst((long)sz, T_INT));
}

/*
 * Converts two arithmetic operands to their common type, and returns it.
 */
static int balance(pl, pr)
int *pl, *pr;
{
    int lk, rk, t;

    lk = KIND(nodes[*pl].type);
    rk = KIND(nodes[*pr].type);
    if (lk < K_TCHAR || lk > K_PTR || rk < K_TCHAR || rk > K_PTR) {
        error("bad operand type", "");
        return T_INT;
    }
    if (lk == K_FLT || rk == K_FLT) {
        error("floating point isn't supported", "");
        return T_INT;
    }
    if (lk == K_ULONG || rk == K_ULONG) t = T_ULONG;
    else if (lk == K_TLONG || rk == K_TLONG) t = T_LONG;
    else if (lk == K_UINT || rk == K_UINT || lk == K_PTR || rk == K_PTR) {
        t = T_UINT;
    }
    else t = T_INT;
    if (ISLONG(t)) {
        *pl = cast(*pl, t);
        *pr = cast(*pr, t);
    }
    return t;
}

static int fold(op, l, r, t)
int op, l, r, t;
{
    long a, b, v;
    unsigned long ua, ub;
    int uns;

    a = nodes[l].val;
    b = nodes[r].val;
    ua = a;
    ub = b;
    uns = ISUNS(t);
    v = 0;
    switch (op) {
    case N_ADD: v = a + b; break;
    case N_SUB: v = a - b; break;
    case N_MUL: v = a * b; break;
    case N_AND: v = a & b; break;
    case N_OR:  v = a | b; break;
    case N_XOR: v = a ^ b; break;
    case N_SHL: v = a << (int)b; break;
    case N_SHR:
        if (uns) v = ua >> (int)b;
        else v = a >> (int)b;
        break;
    case N_DIV:
    case N_MOD:
        if (!b) error("division by zero", "");
        else if (uns) v = op == N_DIV ? ua / ub : ua % ub;
        else v = op == N_DIV ? a / b : a % b;
        break;
    case N_EQ: v = a == b; break;
    case N_NE: v = a != b; break;
    case N_LT: v = uns ? ua < ub : a < b; break;
    case N_GE: v = uns ? ua >= ub : a >= b; break;
    case N_LE: v = uns ? ua <= ub : a <= b; break;
    case N_GT: v = uns ? ua > ub : a > b; break;
    case N_LAND: v = a && b; break;
    case N_LOR: v = a || b; break;
    }
    if (op >= N_EQ || op == N_LAND || op == N_LOR) t = T_INT;
    return konst(norm(v, t), t);
}

static int binop(op, l, r)
int op, l, r;
{
    int lt, rt, t, n;
    unsigned sz;

    l = rvalue(l);
    r = rvalue(r);
    lt = nodes[l].type;
    rt = nodes[r].type;
    if (op == N_LAND || op == N_LOR) {
        if (nodes[l].op == N_CONST && nodes[r].op == N_CONST) {
            return fold(op, l, r, T_INT);
        }
        return mk(op, T_INT, l, r);
    }
    if (ISPTR(lt) || ISPTR(rt)) {
        if (op == N_ADD) {
            if (ISPTR(rt)) {
                n = l; l = r; r = n;
                lt = rt;
            }
            return addnode(l, scale(cast(r, T_INT), elsize(lt)), lt);
        }
        if (op == N_SUB && ISPTR(lt)) {
            if (!ISPTR(rt)) {
                r = scale(cast(r, T_INT), elsize(lt));
                if (nodes[r].op == N_CONST) {
                    return addnode(l, konst(-nodes[r].val, T_INT), lt);
                }
                return mk(N_SUB, lt, l, r);
            }
            n = mk(N_SUB, T_INT, l, r);
            sz = elsize(lt);
            if (sz > 1) n = binop(N_DIV, n, konst((long)sz, T_INT));
            return n;
        }
        if (op >= N_EQ) {
            if (!ISPTR(lt)) l = cast(l, T_UINT);
            if (!ISPTR(rt)) r = cast(r, T_UINT);
            if (nodes[l].op == N_CONST && nodes[r].op == N_CONST) {
                return fold(op, l, r, T_UINT);
            }
            n = mk(op, T_INT, l, r);
            nodes[n].val = 1;
            return n;
        }
        error("bad pointer operation", "");
        return l;
    }
    if (op == N_SHL || op == N_SHR) {
        r = cast(r, T_INT);
        t = balance(&l, &l);
    }
    else t = balance(&l, &r);
    if (nodes[l].op == N_CONST && nodes[r].op == N_CONST) {
        return fold(op, l, r, t);
    }
    if (op >= N_EQ) {
        n = mk(op, T_INT, l, r);
        nodes[n].val = ISUNS(t);
        nodes[n].sym = ISLONG(t);
        return n;
    }
    if (nodes[l].op == N_CONST && (op == N_ADD || op == N_MUL ||
        op == N_AND || op == N_OR || op == N_XOR)) {
        n = l; l = r; r = n;
    }
    if (nodes[r].op == N_CONST && !ISLONG(t)) {
        if (op == N_ADD) return addnode(l, r, t);
        if (op == N_SUB) return addnode(l, konst(-nodes[r].val, T_INT), t);
        if (op == N_MUL && nodes[r].val == 1) return l;
    }
    return mk(op, t, l, r);
}

/*
 * Returns the node for a name whose symbol is s (or zero if it has none).
 */
static int nameref(name, s)
char *name;
int s;
{
    int n, t;
    struct sym *sp;

    if (!s) {
        if (tok == '(') s = newglobal(name, T_FUNCINT);
        else {
            error("%s is undefined", name);
            if (level) s = newsym(name, NS_ORD, C_AUTO, T_INT);
            else s = newglobal(name, T_INT);
        }
    }
    sp = &syms[s];
    t = sp->type;
    switch (sp->cls) {
    case C_ENUM:
        return konst((long)(int)sp->val, T_INT);
    case C_AUTO:
        n = mk(N_ADDRL, T_INT, 0, 0);
        nodes[n].val = (int)sp->val;
        return mk(N_DEREF, t, n, 0);
    case C_GLOBAL:
        n = mk(N_ADDRG, t, 0, 0);
        nodes[n].sym = s;
        if (KIND(t) == K_FUNC) return n;
        return mk(N_DEREF, t, n, 0);
    }
    error("%s isn't a variable", name);
    return konst(0L, T_INT);
}

static int primary()
{
    int n, s, i;
    unsigned off;
    char name[NAMELEN];

    if (havepend) {
        havepend = 0;
        return nameref(pendname, pendsym);
    }
    switch (tok) {
    case T_ID:
        strcpy(name, tokstr);
        s = toksym;
        gettok();
        return nameref(name, s);
    case T_NUM:
        n = konst(tokval, toktype);
        gettok();
        return n;
    case T_STR:
        off = constoff;
        for (i = 0; i <= toklen; i++) dput(SEG_CONST, tokstr[i] & 255);
        n = mk(N_ADDRG, T_PCHAR, SEG_CONST, 0);
        nodes[n].val = off;
        gettok();
        return n;
    }
    error("syntax error", "");
    gettok();
    return konst(0L, T_INT);
}

static int incdec(op, n)
int op, n;
{
    int t, m;

    if (nodes[n].op != N_DEREF) {
        error("lvalue required", "");
        return n;
    }
    t = nodes[n].type;
    m = mk(op, t, n, 0);
    nodes[m].val = ISPTR(t) ? elsize(t) : 1;
    return m;
}

static int postfix(n)
int n;
{
    int t, ft, pl, pc, head, tail, a, i, k, m, pt;

    for (;;) {
        switch (tok) {
        case '[':
            gettok();
            n = binop(N_ADD, n, expr());
            expect(']');
            t = nodes[n].type;
            if (!ISPTR(t)) error("not an array or pointer", "");
            else n = mk(N_DEREF, types[t].base, n, 0);
            break;
        case '(':
            gettok();
            if (nodes[n].op != N_ADDRG || KIND(nodes[n].type) != K_FUNC) {
                n = rvalue(n);
            }
            ft = nodes[n].type;
            if (ISPTR(ft)) ft = types[ft].base;
            if (KIND(ft) != K_FUNC) {
                error("not a function", "");
                ft = T_FUNCINT;
            }
            pl = types[ft].aux;
            pc = pl ? ptypes[pl] : 0;
            head = tail = 0;
            i = 0;
            while (tok != ')' && tok != T_EOF) {
                a = rvalue(assign());
                k = KIND(nodes[a].type);
                if (k == K_STR || k == K_FLT || k == K_TVOID) {
                    error("unsupported argument type", "");
                }
                else if (i < pc) {
                    pt = ptypes[pl + 1 + i];
                    if (KIND(pt) != K_STR && KIND(pt) != K_FLT) {
                        a = cast(a, pt);
                    }
                }
                a = mk(N_ARG, nodes[a].type, a, 0);
                if (tail) nodes[tail].right = a;
                else head = a;
                tail = a;
                i++;
                if (tok != ',') break;
                gettok();
            }
            expect(')');
            n = mk(N_CALL, types[ft].base, n, head);
            break;
        case '.':
        case T_ARROW:
            if (tok == '.') {
                t = nodes[n].type;
                if (nodes[n].op != N_DEREF || KIND(t) != K_STR) {
                    error("not a struct", "");
                    t = 0;
                }
                else n = copyn(nodes[n].left, T_UINT);
            }
            else {
                n = rvalue(n);
                t = nodes[n].type;
                if (!ISPTR(t) || KIND(types[t].base) != K_STR) {
                    error("not a pointer to a struct", "");
                    t = 0;
                }
                else t = types[t].base;
            }
            gettok();
            if (tok != T_ID) error("member name expected", "");
            else if (t) {
                m = lookupmem(tokstr, t);
                if (!m) error("%s isn't a member", tokstr);
                else {
                    n = addnode(n, konst((long)syms[m].val, T_INT), T_UINT);
                    n = mk(N_DEREF, syms[m].type, n, 0);
                }
            }
            gettok();
            break;
        case T_INC:
            gettok();
            n = incdec(N_POSTINC, n);
            break;
        case T_DEC:
            gettok();
            n = incdec(N_POSTDEC, n);
            break;
        default:
            return n;
        }
    }
}

static int unary()
{
    int n, t, op;

    if (havepend) return postfix(primary());
    switch (tok) {
    case '-':
    case '~':
        op = tok == '-' ? N_NEG : N_NOT;
        gettok();
        n = rvalue(unary());
        t = balance(&n, &n);
        if (nodes[n].op == N_CONST) {
            return konst(norm(op == N_NEG ? -nodes[n].val : ~nodes[n].val, t),
                         t);
        }
        return mk(op, t, n, 0);
    case '+':
        gettok();
        return rvalue(unary());
    case '!':
        gettok();
        n = rvalue(unary());
        if (nodes[n].op == N_CONST) return konst((long)!nodes[n].val, T_INT);
        return mk(N_LNOT, T_INT, n, 0);
    case '*':
        gettok();
        n = rvalue(unary());
        t = nodes[n].type;
        if (!ISPTR(t)) {
            error("not a pointer", "");
            return n;
        }
        if (KIND(types[t].base) == K_FUNC) return n;
        return mk(N_DEREF, types[t].base, n, 0);
    case '&':
        gettok();
        n = unary();
        if (nodes[n].op == N_DEREF) {
            return copyn(nodes[n].left, ptrto(nodes[n].type));
        }
        if (nodes[n].op != N_ADDRG) error("lvalue required", "");
        return rvalue(n);
    case T_INC:
        gettok();
        return incdec(N_PREINC, unary());
    case T_DEC:
        gettok();
        return incdec(N_PREDEC, unary());
    case K_SIZEOF:
        gettok();
        if (tok == '(') {
            gettok();
            if (istypename()) {
                t = typename();
                expect(')');
                return konst((long)tsize(t), T_INT);
            }
            n = expr();
            expect(')');
            n = postfix(n);
        }
        else n = unary();
        return konst((long)tsize(nodes[n].type), T_INT);
    case '(':
        gettok();
        if (istypename()) {
            t = typename();
            expect(')');
            return cast(rvalue(unary()), t);
        }
        n = expr();
        expect(')');
        return postfix(n);
    }
    return postfix(primary());
}

/*
 * Returns the precedence of a binary operator's token (or zero), and its
 * node's operator.
 */
static int binprec(t, pop)
int t, *pop;
{
    switch (t) {
    case T_OROR:   *pop = N_LOR;  return 1;
    case T_ANDAND: *pop = N_LAND; return 2;
    case '|':      *pop = N_OR;   return 3;
    case '^':      *pop = N_XOR;  return 4;
    case '&':      *pop = N_AND;  return 5;
    case T_EQ:     *pop = N_EQ;   return 6;
    case T_NE:     *pop = N_NE;   return 6;
    case '<':      *pop = N_LT;   return 7;
    case '>':      *pop = N_GT;   return 7;
    case T_LE:     *pop = N_LE;   return 7;
    case T_GE:     *pop = N_GE;   return 7;
    case T_SHL:    *pop = N_SHL;  return 8;
    case T_SHR:    *pop = N_SHR;  return 8;
    case '+':      *pop = N_ADD;  return 9;
    case '-':      *pop = N_SUB;  return 9;
    case '*':      *pop = N_MUL;  return 10;
    case '/':      *pop = N_DIV;  return 10;
    case '%':      *pop = N_MOD;  return 10;
    }
    return 0;
}

static int binary(p)
int p;
{
    int l, q, op;

    l = unary();
    for (;;) {
        q = binprec(tok, &op);
        if (q < p) return l;
        gettok();
        l = binop(op, l, binary(q + 1));
    }
}

static int cond()
{
    int c, a, b, t;

    c = binary(1);
    if (tok != '?') return c;
    gettok();
    c = rvalue(c);
    a = rvalue(expr());
    expect(':');
    b = rvalue(cond());
    if (ISARITH(nodes[a].type) && ISARITH(nodes[b].type)) {
        t = balance(&a, &b);
    }
    else if (ISPTR(nodes[a].type)) {
        t = nodes[a].type;
        b = cast(b, t);
    }
    else if (ISPTR(nodes[b].type)) {
        t = nodes[b].type;
        a = cast(a, t);
    }
    else t = nodes[a].type;
    if (nodes[c].op == N_CONST) return nodes[c].val ? a : b;
    return mk(N_COND, t, c, mk(N_PAIR, t, a, b));
}

/*
 * Builds an assignment with an operator (eg, +=).  An operation that has
 * no code of its own (see gasgop in gen.c) becomes a plain assignment, if
 * the lvalue can be evaluated twice.
 */
static int asgop(op, l, r)
int op, l, r;
{
    int lt, n, simple, pure;

    lt = nodes[l].type;
    simple = op == N_ADD || op == N_SUB || op == N_AND || op == N_OR ||
             op == N_XOR;
    pure = nodes[nodes[l].left].op == N_ADDRG ||
           nodes[nodes[l].left].op == N_ADDRL;
    if (ISPTR(lt)) {
        if (op != N_ADD && op != N_SUB) {
            error("bad pointer operation", "");
            return l;
        }
        r = scale(cast(r, T_INT), elsize(lt));
    }
    else if (!ISARITH(lt) || !ISARITH(nodes[r].type)) {
        error("bad operand type", "");
        return l;
    }
    else if (op == N_SHL || op == N_SHR) r = cast(r, T_INT);
    else if (ISLONG(lt)) r = cast(r, lt);
    else if (ISLONG(nodes[r].type) && simple) r = cast(r, T_INT);
    if (ISLONG(nodes[r].type) && !ISLONG(lt) && !pure) {
        error("unsupported long operation", "");
        return l;
    }
    if (pure && (ISLONG(lt) && !simple || ISLONG(nodes[r].type) &&
        !ISLONG(lt))) {
        return mk(N_ASSIGN, lt, l, cast(binop(op, l, r), lt));
    }
    n = mk(N_ASGOP, lt, l, r);
    nodes[n].sym = op;
    nodes[n].val = ISUNS(lt) || op != N_SHR && ISUNS(nodes[r].type);
    return n;
}

int assign()
{
    int l, r, op, lt;

    l = cond();
    if (tok != '=' && tok != T_ASGOP) return l;
    op = tok == '=' ? 0 : (int)tokval;
    gettok();
    r = rvalue(assign());
    lt = nodes[l].type;
    if (nodes[l].op != N_DEREF || KIND(lt) == K_ARRAY) {
        error("lvalue required", "");
        return r;
    }
    if (op) return asgop(op, l, r);
    if (KIND(lt) == K_STR) {
        if (nodes[r].type != lt || nodes[r].op != N_DEREF) {
            error("type mismatch", "");
            return l;
        }
        return mk(N_ASSIGN, lt, l, r);
    }
    return mk(N_ASSIGN, lt, l, cast(r, lt));
}

int expr()
{
    int l, r;

    l = assign();
    while (tok == ',') {
        gettok();
        r = rvalue(assign());
        l = mk(N_COMMA, nodes[r].type, l, r);
    }
    return l;
}

/*
 * Parses an expression that is all of a statement (or of a part of one), so
 * the nodes of the last one can be reused.
 */
int fullexpr()
{
    nodetop = 1;
    return expr();
}

long constexpr()
{
    int n;

    n = cond();
    if (nodes[n].op != N_CONST) {
        error("constant expected", "");
        return 0;
    }
    return nodes[n].val;
}
