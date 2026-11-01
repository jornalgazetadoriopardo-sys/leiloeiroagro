import { salvarLeilao } from '../acoes';
import { FormAcao } from '../componentes';

export function FormLeilao({ leilao }: {
  leilao?: { id: string; titulo: string; descricao: string | null; abre: string; fecha: string; intervaloMin: number };
}) {
  return (
    <FormAcao acao={salvarLeilao} botao={leilao ? 'Salvar alterações' : 'Criar leilão'} classeBotao="btn-primary btn-bloco" className="bloco">
      <h2>{leilao ? 'Dados do leilão' : 'Novo leilão'}</h2>
      {leilao && <input type="hidden" name="id" value={leilao.id} />}
      <div className="grade-form">
        <div className="campo largo"><label htmlFor="titulo">Nome</label>
          <input id="titulo" name="titulo" defaultValue={leilao?.titulo} placeholder="Ex.: Leilão de garrotes – novembro" /></div>
        <div className="campo"><label htmlFor="abre_em">Abre para lances em</label>
          <input id="abre_em" name="abre_em" type="datetime-local" defaultValue={leilao?.abre} /></div>
        <div className="campo"><label htmlFor="primeiro_fechamento_em">Primeiro lote fecha em</label>
          <input id="primeiro_fechamento_em" name="primeiro_fechamento_em" type="datetime-local" defaultValue={leilao?.fecha} /></div>
        <div className="campo"><label htmlFor="intervalo_min">Minutos entre um lote e outro</label>
          <input id="intervalo_min" name="intervalo_min" inputMode="numeric" defaultValue={leilao?.intervaloMin ?? 2} /></div>
        <div className="campo largo"><label htmlFor="descricao">Descrição (opcional)</label>
          <textarea id="descricao" name="descricao" defaultValue={leilao?.descricao ?? ''} /></div>
      </div>
      <p className="note" style={{ marginTop: 10 }}>Horários de Brasília. Os lotes fecham em sequência; a prorrogação de um não empurra os outros.</p>
    </FormAcao>
  );
}
