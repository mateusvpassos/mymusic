// Testes das regras do Firestore no emulador.
// Rodar: npm test   (sobe o emulador, roda e derruba)
import { test, before, after, beforeEach } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment, assertSucceeds, assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, writeBatch, collection, query, where, getDocs,
} from 'firebase/firestore';

const DONO = 'mateus@x.com', ANA = 'ana@x.com', BIA = 'bia@x.com', FORA = 'intruso@x.com';
let env;

const db = (email) => env.authenticatedContext(email.split('@')[0], { email }).firestore();
const g = 'g1';
const musica = (dono, extra = {}) => ({
  id: 'm1', title: 'Teu Óleo Santo', dono, editores: [], versao: 1, apagada: false,
  updatedAt: '2026-10-03T10:00:00.000', ...extra,
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-mymusic',
    firestore: { rules: readFileSync('firestore.rules', 'utf8'), host: '127.0.0.1', port: 8188 },
  });
});
after(() => env.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    await setDoc(doc(f, 'grupos', g), { nome: 'Ministério', dono: DONO, membros: [DONO, ANA, BIA] });
    await setDoc(doc(f, `grupos/${g}/musicas/m1`), musica(DONO));
  });
});

test('quem não é do grupo não lê nada', async () => {
  await assertFails(getDoc(doc(db(FORA), `grupos/${g}/musicas/m1`)));
  await assertFails(getDoc(doc(db(FORA), 'grupos', g)));
});

test('membro acha o grupo pelo próprio e-mail', async () => {
  const q = query(collection(db(ANA), 'grupos'), where('membros', 'array-contains', ANA));
  const r = await assertSucceeds(getDocs(q));
  if (r.size !== 1) throw new Error('não achou o grupo');
});

test('quem cria é o dono (não dá p/ criar em nome de outro)', async () => {
  await assertSucceeds(setDoc(doc(db(ANA), `grupos/${g}/musicas/m2`), musica(ANA, { id: 'm2' })));
  await assertFails(setDoc(doc(db(ANA), `grupos/${g}/musicas/m3`), musica(DONO, { id: 'm3' })));
});

test('membro sem permissão não edita; editor edita; ninguém troca o dono', async () => {
  await assertFails(updateDoc(doc(db(ANA), `grupos/${g}/musicas/m1`), { title: 'x' }));
  await env.withSecurityRulesDisabled((ctx) =>
    updateDoc(doc(ctx.firestore(), `grupos/${g}/musicas/m1`), { editores: [ANA] }));
  await assertSucceeds(updateDoc(doc(db(ANA), `grupos/${g}/musicas/m1`), { title: 'x' }));
  await assertFails(updateDoc(doc(db(ANA), `grupos/${g}/musicas/m1`), { dono: ANA }));
  // editor não dá permissão p/ outros nem apaga
  await assertFails(updateDoc(doc(db(ANA), `grupos/${g}/musicas/m1`), { editores: [ANA, BIA] }));
  await assertFails(updateDoc(doc(db(ANA), `grupos/${g}/musicas/m1`), { apagada: true }));
  await assertSucceeds(updateDoc(doc(db(DONO), `grupos/${g}/musicas/m1`), { apagada: true }));
});

test('confiança: dono libera alguém p/ todas as músicas dele', async () => {
  await assertFails(setDoc(doc(db(ANA), `grupos/${g}/confianca/${DONO}`), { editores: [ANA] }));
  await assertSucceeds(setDoc(doc(db(DONO), `grupos/${g}/confianca/${DONO}`), { editores: [BIA] }));
  await assertSucceeds(updateDoc(doc(db(BIA), `grupos/${g}/musicas/m1`), { title: 'y' }));
  await assertFails(updateDoc(doc(db(ANA), `grupos/${g}/musicas/m1`), { title: 'y' }));
});

test('versão: só junto com gravação permitida, e imutável', async () => {
  const f = db(DONO);
  const b = writeBatch(f);
  b.update(doc(f, `grupos/${g}/musicas/m1`), { title: 'nova', versao: 2 });
  b.set(doc(f, `grupos/${g}/musicas/m1/versoes/2`), { n: 2, por: DONO, song: {} });
  await assertSucceeds(b.commit());
  await assertFails(updateDoc(doc(f, `grupos/${g}/musicas/m1/versoes/2`), { n: 3 }));
  await assertFails(deleteDoc(doc(f, `grupos/${g}/musicas/m1/versoes/2`)));
  await assertFails(setDoc(doc(db(ANA), `grupos/${g}/musicas/m1/versoes/3`), { n: 3, por: ANA, song: {} }));
  // versão em nome de outro
  await assertFails(setDoc(doc(f, `grupos/${g}/musicas/m1/versoes/4`), { n: 4, por: ANA, song: {} }));
});

test('sugestão: membro sugere, dono decide, autor pode desistir', async () => {
  const sug = { songId: 'm1', por: ANA, status: 'pendente', song: { title: 'sugerido' } };
  await assertSucceeds(setDoc(doc(db(ANA), `grupos/${g}/sugestoes/s1`), sug));
  await assertFails(setDoc(doc(db(ANA), `grupos/${g}/sugestoes/s2`), { ...sug, por: BIA }));
  await assertFails(setDoc(doc(db(FORA), `grupos/${g}/sugestoes/s3`), { ...sug, por: FORA }));
  // outra pessoa sem permissão não decide
  await assertFails(updateDoc(doc(db(BIA), `grupos/${g}/sugestoes/s1`),
    { status: 'aceita', decididoPor: BIA }));
  // autor não aceita a própria
  await assertFails(updateDoc(doc(db(ANA), `grupos/${g}/sugestoes/s1`),
    { status: 'aceita', decididoPor: ANA }));
  // dono não pode reescrever o conteúdo da sugestão ao decidir
  await assertFails(updateDoc(doc(db(DONO), `grupos/${g}/sugestoes/s1`),
    { status: 'aceita', decididoPor: DONO, song: {} }));
  await assertSucceeds(updateDoc(doc(db(DONO), `grupos/${g}/sugestoes/s1`),
    { status: 'aceita', decididoPor: DONO, decididoEm: 'agora' }));
  // decidida não muda mais
  await assertFails(updateDoc(doc(db(DONO), `grupos/${g}/sugestoes/s1`),
    { status: 'recusada', decididoPor: DONO }));

  await setDoc(doc(db(ANA), `grupos/${g}/sugestoes/s4`), sug);
  await assertSucceeds(updateDoc(doc(db(ANA), `grupos/${g}/sugestoes/s4`),
    { status: 'cancelada', decididoEm: 'agora' }));
});

test('grupo: só o dono convida', async () => {
  await assertFails(updateDoc(doc(db(ANA), 'grupos', g), { membros: [DONO, ANA, BIA, FORA] }));
  await assertSucceeds(updateDoc(doc(db(DONO), 'grupos', g), { membros: [DONO, ANA, BIA, FORA] }));
  await assertFails(updateDoc(doc(db(DONO), 'grupos', g), { dono: ANA }));
});

test('apagar de verdade não pode (vira lápide)', async () => {
  await assertFails(deleteDoc(doc(db(DONO), `grupos/${g}/musicas/m1`)));
});
