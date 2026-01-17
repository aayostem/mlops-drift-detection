"""Basic test to verify pytest works"""
import pytest

def test_addition():
    assert 1 + 1 == 2

def test_subtraction():
    assert 3 - 1 == 2

class TestMath:
    def test_multiplication(self):
        assert 2 * 3 == 6
    
    def test_division(self):
        assert 8 / 2 == 4
