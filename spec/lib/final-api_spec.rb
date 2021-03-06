require 'spec_helper'

describe FinalAPI do

  describe '#custom_sum_results' do
    context 'when test contains errored state' do
      it 'returns errored' do
        expect(FinalAPI.send(:custom_sum_results, { error: 1 })).to eq 'errored'
        expect(FinalAPI.send(
          :custom_sum_results,
          { errored: 1, failed: 4, passed: 3, created: 1 }
        )).to eq 'errored'
      end
    end

    context 'when test contains failed and no errored' do
      it 'returns errored' do
        expect(FinalAPI.send(:custom_sum_results, { failed: 1 })).to eq 'failed'
        expect(FinalAPI.send(
          :custom_sum_results,
          { failed: 4, passed: 3, pending: 4, created: 1 }
        )).to eq 'failed'
      end
    end

    context 'when no failed, errored and created or pending exists' do
      it 'returns pending' do
        expect(FinalAPI.send(:custom_sum_results, { created: 1 })).to eq 'created'
        expect(FinalAPI.send(:custom_sum_results, { pending: 1 })).to eq 'created'
        expect(FinalAPI.send(
          :custom_sum_results,
          { passed: 1, skipped: 1, pending: 1, knownBug: 1 }
        )).to eq 'created'
      end
    end

    context 'when no failed, errored and one pased' do
      it 'return passed when only skipped, notPerformed knownBug are present' do
        expect(FinalAPI.send(:custom_sum_results, { passed: 1 })).to eq 'passed'
        expect(FinalAPI.send(
          :custom_sum_results,
          { passed: 1, skipped: 1, notPerformed: 1, knownBug: 1 }
        )).to eq 'passed'
      end
    end

    context 'when unknown state' do
      it 'returns errored' do
        expect(FinalAPI.send(:custom_sum_results, { xxx: 1 })).to eq 'errored'
      end
    end
  end
end
