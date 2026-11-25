import unittest
from analyst_upgrade import signed_contributions, ratio_contributions, apply_upgrade

class MetricUpgradeTests(unittest.TestCase):
    def test_gross_contributions_do_not_explode_when_net_near_zero(self):
        rows=signed_contributions([{'delta':1000},{'delta':-999}])
        self.assertAlmostEqual(sum(abs(r['contribution']) for r in rows),1)
        self.assertLess(abs(rows[0]['contribution']),1)

    def test_ratio_bridge_closes_to_ratio_of_sums_not_average_rates(self):
        cur=[(10,100),(90,300)]; base=[(20,200),(10,100)]
        self.assertAlmostEqual(sum(ratio_contributions(cur,base)),100/400-30/300)
        self.assertEqual(ratio_contributions([(0,0)],[(1,1)]),[None])

    def test_metric_denominators_are_independent(self):
        revenue=signed_contributions([{'delta':10},{'delta':-30}])
        dau=signed_contributions([{'delta':100},{'delta':-100}])
        self.assertEqual(revenue[0]['contribution'],.25)
        self.assertEqual(dau[0]['contribution'],.5)

if __name__=='__main__': unittest.main()
